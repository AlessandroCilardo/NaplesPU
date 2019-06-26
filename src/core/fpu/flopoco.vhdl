--------------------------------------------------------------------------------
--                         Fix2FP_0_63_S_11_52_LZOCS
--                 (LZOCShifter_63_to_64_counting_64_uid184)
-- This operator is part of the Infinite Virtual Library FloPoCoLib
-- All rights reserved 
-- Authors: Florent de Dinechin, Bogdan Pasca (2007)
--------------------------------------------------------------------------------
-- Pipeline depth: 5 cycles

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library std;
use std.textio.all;
library work;

entity Fix2FP_0_63_S_11_52_LZOCS is
   port ( clk, rst : in std_logic;
          I : in  std_logic_vector(62 downto 0);
          OZb : in std_logic;
          Count : out  std_logic_vector(5 downto 0);
          O : out  std_logic_vector(63 downto 0)   );
end entity;

architecture arch of Fix2FP_0_63_S_11_52_LZOCS is
signal level6 :  std_logic_vector(62 downto 0);
signal sozb, sozb_d1, sozb_d2, sozb_d3, sozb_d4, sozb_d5 : std_logic;
signal count5, count5_d1, count5_d2, count5_d3, count5_d4, count5_d5 : std_logic;
signal level5, level5_d1 :  std_logic_vector(62 downto 0);
signal count4, count4_d1, count4_d2, count4_d3, count4_d4 : std_logic;
signal level4, level4_d1 :  std_logic_vector(62 downto 0);
signal count3, count3_d1, count3_d2, count3_d3 : std_logic;
signal level3, level3_d1 :  std_logic_vector(62 downto 0);
signal count2, count2_d1, count2_d2 : std_logic;
signal level2, level2_d1 :  std_logic_vector(62 downto 0);
signal count1, count1_d1 : std_logic;
signal level1, level1_d1 :  std_logic_vector(62 downto 0);
signal count0 : std_logic;
signal level0 :  std_logic_vector(62 downto 0);
signal sCount :  std_logic_vector(5 downto 0);
begin
   process(clk)
      begin
         if clk'event and clk = '1' then
            sozb_d1 <=  sozb;
            sozb_d2 <=  sozb_d1;
            sozb_d3 <=  sozb_d2;
            sozb_d4 <=  sozb_d3;
            sozb_d5 <=  sozb_d4;
            count5_d1 <=  count5;
            count5_d2 <=  count5_d1;
            count5_d3 <=  count5_d2;
            count5_d4 <=  count5_d3;
            count5_d5 <=  count5_d4;
            level5_d1 <=  level5;
            count4_d1 <=  count4;
            count4_d2 <=  count4_d1;
            count4_d3 <=  count4_d2;
            count4_d4 <=  count4_d3;
            level4_d1 <=  level4;
            count3_d1 <=  count3;
            count3_d2 <=  count3_d1;
            count3_d3 <=  count3_d2;
            level3_d1 <=  level3;
            count2_d1 <=  count2;
            count2_d2 <=  count2_d1;
            level2_d1 <=  level2;
            count1_d1 <=  count1;
            level1_d1 <=  level1;
         end if;
      end process;
   level6 <= I ;
   sozb<= OZb;
   count5<= '1' when level6(62 downto 31) = (62 downto 31=>sozb) else '0';
   level5<= level6(62 downto 0) when count5='0' else level6(30 downto 0) & (31 downto 0 => '0');

   ----------------Synchro barrier, entering cycle 1----------------
   count4<= '1' when level5_d1(62 downto 47) = (62 downto 47=>sozb_d1) else '0';
   level4<= level5_d1(62 downto 0) when count4='0' else level5_d1(46 downto 0) & (15 downto 0 => '0');

   ----------------Synchro barrier, entering cycle 2----------------
   count3<= '1' when level4_d1(62 downto 55) = (62 downto 55=>sozb_d2) else '0';
   level3<= level4_d1(62 downto 0) when count3='0' else level4_d1(54 downto 0) & (7 downto 0 => '0');

   ----------------Synchro barrier, entering cycle 3----------------
   count2<= '1' when level3_d1(62 downto 59) = (62 downto 59=>sozb_d3) else '0';
   level2<= level3_d1(62 downto 0) when count2='0' else level3_d1(58 downto 0) & (3 downto 0 => '0');

   ----------------Synchro barrier, entering cycle 4----------------
   count1<= '1' when level2_d1(62 downto 61) = (62 downto 61=>sozb_d4) else '0';
   level1<= level2_d1(62 downto 0) when count1='0' else level2_d1(60 downto 0) & (1 downto 0 => '0');

   ----------------Synchro barrier, entering cycle 5----------------
   count0<= '1' when level1_d1(62 downto 62) = (62 downto 62=>sozb_d5) else '0';
   level0<= level1_d1(62 downto 0) when count0='0' else level1_d1(61 downto 0) & (0 downto 0 => '0');

   O <= level0&(0 downto 0 => '0');
   sCount <= count5_d5 & count4_d4 & count3_d3 & count2_d2 & count1_d1 & count0;
   Count <= sCount;
end architecture;

--------------------------------------------------------------------------------
--                   Fix2FP_0_63_S_11_52exponentConversion
--                         (IntAdder_11_f400_uid187)
-- This operator is part of the Infinite Virtual Library FloPoCoLib
-- All rights reserved 
-- Authors: Bogdan Pasca, Florent de Dinechin (2008-2010)
--------------------------------------------------------------------------------
-- Pipeline depth: 0 cycles

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library std;
use std.textio.all;
library work;

entity Fix2FP_0_63_S_11_52exponentConversion is
   port ( clk, rst : in std_logic;
          X : in  std_logic_vector(10 downto 0);
          Y : in  std_logic_vector(10 downto 0);
          Cin : in std_logic;
          R : out  std_logic_vector(10 downto 0)   );
end entity;

architecture arch of Fix2FP_0_63_S_11_52exponentConversion is
begin
   process(clk)
      begin
         if clk'event and clk = '1' then
         end if;
      end process;
   --Classical
    R <= X + Y + Cin;
end architecture;

--------------------------------------------------------------------------------
--                      Fix2FP_0_63_S_11_52exponentFinal
--                         (IntAdder_12_f400_uid194)
-- This operator is part of the Infinite Virtual Library FloPoCoLib
-- All rights reserved 
-- Authors: Bogdan Pasca, Florent de Dinechin (2008-2010)
--------------------------------------------------------------------------------
-- Pipeline depth: 0 cycles

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library std;
use std.textio.all;
library work;

entity Fix2FP_0_63_S_11_52exponentFinal is
   port ( clk, rst : in std_logic;
          X : in  std_logic_vector(11 downto 0);
          Y : in  std_logic_vector(11 downto 0);
          Cin : in std_logic;
          R : out  std_logic_vector(11 downto 0)   );
end entity;

architecture arch of Fix2FP_0_63_S_11_52exponentFinal is
begin
   process(clk)
      begin
         if clk'event and clk = '1' then
         end if;
      end process;
   --Classical
    R <= X + Y + Cin;
end architecture;

--------------------------------------------------------------------------------
--                          Fix2FP_0_63_S_11_52zeroD
--                         (IntAdder_64_f400_uid201)
-- This operator is part of the Infinite Virtual Library FloPoCoLib
-- All rights reserved 
-- Authors: Bogdan Pasca, Florent de Dinechin (2008-2010)
--------------------------------------------------------------------------------
-- Pipeline depth: 1 cycles

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library std;
use std.textio.all;
library work;

entity Fix2FP_0_63_S_11_52zeroD is
   port ( clk, rst : in std_logic;
          X : in  std_logic_vector(63 downto 0);
          Y : in  std_logic_vector(63 downto 0);
          Cin : in std_logic;
          R : out  std_logic_vector(63 downto 0)   );
end entity;

architecture arch of Fix2FP_0_63_S_11_52zeroD is
signal s_sum_l0_idx0 :  std_logic_vector(42 downto 0);
signal s_sum_l0_idx1, s_sum_l0_idx1_d1 :  std_logic_vector(22 downto 0);
signal sum_l0_idx0, sum_l0_idx0_d1 :  std_logic_vector(41 downto 0);
signal c_l0_idx0, c_l0_idx0_d1 :  std_logic_vector(0 downto 0);
signal sum_l0_idx1 :  std_logic_vector(21 downto 0);
signal c_l0_idx1 :  std_logic_vector(0 downto 0);
signal s_sum_l1_idx1 :  std_logic_vector(22 downto 0);
signal sum_l1_idx1 :  std_logic_vector(21 downto 0);
signal c_l1_idx1 :  std_logic_vector(0 downto 0);
begin
   process(clk)
      begin
         if clk'event and clk = '1' then
            s_sum_l0_idx1_d1 <=  s_sum_l0_idx1;
            sum_l0_idx0_d1 <=  sum_l0_idx0;
            c_l0_idx0_d1 <=  c_l0_idx0;
         end if;
      end process;
   --Alternative
   s_sum_l0_idx0 <= ( "0" & X(41 downto 0)) + ( "0" & Y(41 downto 0)) + Cin;
   s_sum_l0_idx1 <= ( "0" & X(63 downto 42)) + ( "0" & Y(63 downto 42));
   sum_l0_idx0 <= s_sum_l0_idx0(41 downto 0);
   c_l0_idx0 <= s_sum_l0_idx0(42 downto 42);
   sum_l0_idx1 <= s_sum_l0_idx1(21 downto 0);
   c_l0_idx1 <= s_sum_l0_idx1(22 downto 22);
   ----------------Synchro barrier, entering cycle 1----------------
   s_sum_l1_idx1 <=  s_sum_l0_idx1_d1 + c_l0_idx0_d1(0 downto 0);
   sum_l1_idx1 <= s_sum_l1_idx1(21 downto 0);
   c_l1_idx1 <= s_sum_l1_idx1(22 downto 22);
   R <= sum_l1_idx1(21 downto 0) & sum_l0_idx0_d1(41 downto 0);
end architecture;

--------------------------------------------------------------------------------
--                    Fix2FP_0_63_S_11_52_fractionConvert
--                         (IntAdder_65_f400_uid208)
-- This operator is part of the Infinite Virtual Library FloPoCoLib
-- All rights reserved 
-- Authors: Bogdan Pasca, Florent de Dinechin (2008-2010)
--------------------------------------------------------------------------------
-- Pipeline depth: 1 cycles

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library std;
use std.textio.all;
library work;

entity Fix2FP_0_63_S_11_52_fractionConvert is
   port ( clk, rst : in std_logic;
          X : in  std_logic_vector(64 downto 0);
          Y : in  std_logic_vector(64 downto 0);
          Cin : in std_logic;
          R : out  std_logic_vector(64 downto 0)   );
end entity;

architecture arch of Fix2FP_0_63_S_11_52_fractionConvert is
signal s_sum_l0_idx0 :  std_logic_vector(42 downto 0);
signal s_sum_l0_idx1, s_sum_l0_idx1_d1 :  std_logic_vector(23 downto 0);
signal sum_l0_idx0, sum_l0_idx0_d1 :  std_logic_vector(41 downto 0);
signal c_l0_idx0, c_l0_idx0_d1 :  std_logic_vector(0 downto 0);
signal sum_l0_idx1 :  std_logic_vector(22 downto 0);
signal c_l0_idx1 :  std_logic_vector(0 downto 0);
signal s_sum_l1_idx1 :  std_logic_vector(23 downto 0);
signal sum_l1_idx1 :  std_logic_vector(22 downto 0);
signal c_l1_idx1 :  std_logic_vector(0 downto 0);
begin
   process(clk)
      begin
         if clk'event and clk = '1' then
            s_sum_l0_idx1_d1 <=  s_sum_l0_idx1;
            sum_l0_idx0_d1 <=  sum_l0_idx0;
            c_l0_idx0_d1 <=  c_l0_idx0;
         end if;
      end process;
   --Alternative
   s_sum_l0_idx0 <= ( "0" & X(41 downto 0)) + ( "0" & Y(41 downto 0)) + Cin;
   s_sum_l0_idx1 <= ( "0" & X(64 downto 42)) + ( "0" & Y(64 downto 42));
   sum_l0_idx0 <= s_sum_l0_idx0(41 downto 0);
   c_l0_idx0 <= s_sum_l0_idx0(42 downto 42);
   sum_l0_idx1 <= s_sum_l0_idx1(22 downto 0);
   c_l0_idx1 <= s_sum_l0_idx1(23 downto 23);
   ----------------Synchro barrier, entering cycle 1----------------
   s_sum_l1_idx1 <=  s_sum_l0_idx1_d1 + c_l0_idx0_d1(0 downto 0);
   sum_l1_idx1 <= s_sum_l1_idx1(22 downto 0);
   c_l1_idx1 <= s_sum_l1_idx1(23 downto 23);
   R <= sum_l1_idx1(22 downto 0) & sum_l0_idx0_d1(41 downto 0);
end architecture;

--------------------------------------------------------------------------------
--                     Fix2FP_0_63_S_11_52_oneSubstracter
--                         (IntAdder_10_f400_uid215)
-- This operator is part of the Infinite Virtual Library FloPoCoLib
-- All rights reserved 
-- Authors: Bogdan Pasca, Florent de Dinechin (2008-2010)
--------------------------------------------------------------------------------
-- Pipeline depth: 0 cycles

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library std;
use std.textio.all;
library work;

entity Fix2FP_0_63_S_11_52_oneSubstracter is
   port ( clk, rst : in std_logic;
          X : in  std_logic_vector(9 downto 0);
          Y : in  std_logic_vector(9 downto 0);
          Cin : in std_logic;
          R : out  std_logic_vector(9 downto 0)   );
end entity;

architecture arch of Fix2FP_0_63_S_11_52_oneSubstracter is
begin
   process(clk)
      begin
         if clk'event and clk = '1' then
         end if;
      end process;
   --Classical
    R <= X + Y + Cin;
end architecture;

--------------------------------------------------------------------------------
--                      Fix2FP_0_63_S_11_52roundingAdder
--                         (IntAdder_64_f400_uid222)
-- This operator is part of the Infinite Virtual Library FloPoCoLib
-- All rights reserved 
-- Authors: Bogdan Pasca, Florent de Dinechin (2008-2010)
--------------------------------------------------------------------------------
-- Pipeline depth: 1 cycles

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library std;
use std.textio.all;
library work;

entity Fix2FP_0_63_S_11_52roundingAdder is
   port ( clk, rst : in std_logic;
          X : in  std_logic_vector(63 downto 0);
          Y : in  std_logic_vector(63 downto 0);
          Cin : in std_logic;
          R : out  std_logic_vector(63 downto 0)   );
end entity;

architecture arch of Fix2FP_0_63_S_11_52roundingAdder is
signal s_sum_l0_idx0 :  std_logic_vector(42 downto 0);
signal s_sum_l0_idx1, s_sum_l0_idx1_d1 :  std_logic_vector(22 downto 0);
signal sum_l0_idx0, sum_l0_idx0_d1 :  std_logic_vector(41 downto 0);
signal c_l0_idx0, c_l0_idx0_d1 :  std_logic_vector(0 downto 0);
signal sum_l0_idx1 :  std_logic_vector(21 downto 0);
signal c_l0_idx1 :  std_logic_vector(0 downto 0);
signal s_sum_l1_idx1 :  std_logic_vector(22 downto 0);
signal sum_l1_idx1 :  std_logic_vector(21 downto 0);
signal c_l1_idx1 :  std_logic_vector(0 downto 0);
begin
   process(clk)
      begin
         if clk'event and clk = '1' then
            s_sum_l0_idx1_d1 <=  s_sum_l0_idx1;
            sum_l0_idx0_d1 <=  sum_l0_idx0;
            c_l0_idx0_d1 <=  c_l0_idx0;
         end if;
      end process;
   --Alternative
   s_sum_l0_idx0 <= ( "0" & X(41 downto 0)) + ( "0" & Y(41 downto 0)) + Cin;
   s_sum_l0_idx1 <= ( "0" & X(63 downto 42)) + ( "0" & Y(63 downto 42));
   sum_l0_idx0 <= s_sum_l0_idx0(41 downto 0);
   c_l0_idx0 <= s_sum_l0_idx0(42 downto 42);
   sum_l0_idx1 <= s_sum_l0_idx1(21 downto 0);
   c_l0_idx1 <= s_sum_l0_idx1(22 downto 22);
   ----------------Synchro barrier, entering cycle 1----------------
   s_sum_l1_idx1 <=  s_sum_l0_idx1_d1 + c_l0_idx0_d1(0 downto 0);
   sum_l1_idx1 <= s_sum_l1_idx1(21 downto 0);
   c_l1_idx1 <= s_sum_l1_idx1(22 downto 22);
   R <= sum_l1_idx1(21 downto 0) & sum_l0_idx0_d1(41 downto 0);
end architecture;

--------------------------------------------------------------------------------
--                            Fix2FP_0_63_S_11_52
-- This operator is part of the Infinite Virtual Library FloPoCoLib
-- All rights reserved 
-- Authors: Radu Tudoran, Bogdan Pasca (2009)
--------------------------------------------------------------------------------
-- Pipeline depth: 8 cycles

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library std;
use std.textio.all;
library work;

entity Fix2FP_0_63_S_11_52 is
   port ( clk, rst : in std_logic;
          I : in  std_logic_vector(63 downto 0);
          O : out  std_logic_vector(11+52+2 downto 0)   );
end entity;

architecture arch of Fix2FP_0_63_S_11_52 is
   component Fix2FP_0_63_S_11_52_LZOCS is
      port ( clk, rst : in std_logic;
             I : in  std_logic_vector(62 downto 0);
             OZb : in std_logic;
             Count : out  std_logic_vector(5 downto 0);
             O : out  std_logic_vector(63 downto 0)   );
   end component;

   component Fix2FP_0_63_S_11_52_fractionConvert is
      port ( clk, rst : in std_logic;
             X : in  std_logic_vector(64 downto 0);
             Y : in  std_logic_vector(64 downto 0);
             Cin : in std_logic;
             R : out  std_logic_vector(64 downto 0)   );
   end component;

   component Fix2FP_0_63_S_11_52_oneSubstracter is
      port ( clk, rst : in std_logic;
             X : in  std_logic_vector(9 downto 0);
             Y : in  std_logic_vector(9 downto 0);
             Cin : in std_logic;
             R : out  std_logic_vector(9 downto 0)   );
   end component;

   component Fix2FP_0_63_S_11_52exponentConversion is
      port ( clk, rst : in std_logic;
             X : in  std_logic_vector(10 downto 0);
             Y : in  std_logic_vector(10 downto 0);
             Cin : in std_logic;
             R : out  std_logic_vector(10 downto 0)   );
   end component;

   component Fix2FP_0_63_S_11_52exponentFinal is
      port ( clk, rst : in std_logic;
             X : in  std_logic_vector(11 downto 0);
             Y : in  std_logic_vector(11 downto 0);
             Cin : in std_logic;
             R : out  std_logic_vector(11 downto 0)   );
   end component;

   component Fix2FP_0_63_S_11_52roundingAdder is
      port ( clk, rst : in std_logic;
             X : in  std_logic_vector(63 downto 0);
             Y : in  std_logic_vector(63 downto 0);
             Cin : in std_logic;
             R : out  std_logic_vector(63 downto 0)   );
   end component;

   component Fix2FP_0_63_S_11_52zeroD is
      port ( clk, rst : in std_logic;
             X : in  std_logic_vector(63 downto 0);
             Y : in  std_logic_vector(63 downto 0);
             Cin : in std_logic;
             R : out  std_logic_vector(63 downto 0)   );
   end component;

signal input :  std_logic_vector(63 downto 0);
signal signSignal, signSignal_d1, signSignal_d2, signSignal_d3, signSignal_d4, signSignal_d5, signSignal_d6, signSignal_d7, signSignal_d8 : std_logic;
signal passedInput :  std_logic_vector(63 downto 0);
signal input2LZOC :  std_logic_vector(62 downto 0);
signal temporalExponent :  std_logic_vector(5 downto 0);
signal temporalFraction :  std_logic_vector(63 downto 0);
signal MSB2Signal :  std_logic_vector(10 downto 0);
signal zeroPadding4Exponent :  std_logic_vector(4 downto 0);
signal valueExponent :  std_logic_vector(10 downto 0);
signal partialConvertedExponent :  std_logic_vector(10 downto 0);
signal biassOfOnes :  std_logic_vector(9 downto 0);
signal biassSignal :  std_logic_vector(10 downto 0);
signal biassSignalBit :  std_logic_vector(11 downto 0);
signal partialConvertedExponentBit :  std_logic_vector(11 downto 0);
signal sign4OU : std_logic;
signal convertedExponentBit :  std_logic_vector(11 downto 0);
signal convertedExponent, convertedExponent_d1, convertedExponent_d2 :  std_logic_vector(10 downto 0);
signal underflowSignal, underflowSignal_d1, underflowSignal_d2, underflowSignal_d3 : std_logic;
signal overflowSignal, overflowSignal_d1, overflowSignal_d2, overflowSignal_d3 : std_logic;
signal minusOne4ZD :  std_logic_vector(63 downto 0);
signal zeroDS :  std_logic_vector(63 downto 0);
signal zeroInput, zeroInput_d1, zeroInput_d2, zeroInput_d3, zeroInput_d4, zeroInput_d5, zeroInput_d6, zeroInput_d7 : std_logic;
signal sign2vector :  std_logic_vector(63 downto 0);
signal tempConvert :  std_logic_vector(63 downto 0);
signal tempConvert0 :  std_logic_vector(64 downto 0);
signal tempPaddingAddSign :  std_logic_vector(63 downto 0);
signal tempAddSign :  std_logic_vector(64 downto 0);
signal tempFractionResult :  std_logic_vector(64 downto 0);
signal correctingExponent, correctingExponent_d1 : std_logic;
signal fractionConverted, fractionConverted_d1 :  std_logic_vector(51 downto 0);
signal firstBitofRest, firstBitofRest_d1 : std_logic;
signal lastBitOfFraction, lastBitOfFraction_d1 : std_logic;
signal minusOne :  std_logic_vector(9 downto 0);
signal fractionRemainder :  std_logic_vector(9 downto 0);
signal zeroFractionResult :  std_logic_vector(9 downto 0);
signal zeroRemainder, zeroRemainder_d1 : std_logic;
signal outputOfMux3 : std_logic;
signal outputOfMux2 : std_logic;
signal outputOfMux1 : std_logic;
signal possibleCorrector4Rounding :  std_logic_vector(63 downto 0);
signal concatenationForRounding :  std_logic_vector(63 downto 0);
signal testC :  std_logic_vector(63 downto 0);
signal testR :  std_logic_vector(63 downto 0);
signal testM : std_logic;
signal roundedResult :  std_logic_vector(63 downto 0);
signal convertedExponentAfterRounding :  std_logic_vector(10 downto 0);
signal convertedFractionAfterRounding :  std_logic_vector(51 downto 0);
signal MSBSelection : std_logic;
signal LSBSelection : std_logic;
signal Selection :  std_logic_vector(1 downto 0);
signal specialBits :  std_logic_vector(1 downto 0);
begin
   process(clk)
      begin
         if clk'event and clk = '1' then
            signSignal_d1 <=  signSignal;
            signSignal_d2 <=  signSignal_d1;
            signSignal_d3 <=  signSignal_d2;
            signSignal_d4 <=  signSignal_d3;
            signSignal_d5 <=  signSignal_d4;
            signSignal_d6 <=  signSignal_d5;
            signSignal_d7 <=  signSignal_d6;
            signSignal_d8 <=  signSignal_d7;
            convertedExponent_d1 <=  convertedExponent;
            convertedExponent_d2 <=  convertedExponent_d1;
            underflowSignal_d1 <=  underflowSignal;
            underflowSignal_d2 <=  underflowSignal_d1;
            underflowSignal_d3 <=  underflowSignal_d2;
            overflowSignal_d1 <=  overflowSignal;
            overflowSignal_d2 <=  overflowSignal_d1;
            overflowSignal_d3 <=  overflowSignal_d2;
            zeroInput_d1 <=  zeroInput;
            zeroInput_d2 <=  zeroInput_d1;
            zeroInput_d3 <=  zeroInput_d2;
            zeroInput_d4 <=  zeroInput_d3;
            zeroInput_d5 <=  zeroInput_d4;
            zeroInput_d6 <=  zeroInput_d5;
            zeroInput_d7 <=  zeroInput_d6;
            correctingExponent_d1 <=  correctingExponent;
            fractionConverted_d1 <=  fractionConverted;
            firstBitofRest_d1 <=  firstBitofRest;
            lastBitOfFraction_d1 <=  lastBitOfFraction;
            zeroRemainder_d1 <=  zeroRemainder;
         end if;
      end process;
   input <= I;
   signSignal<=input(63);
   passedInput<=input(63 downto 0);
   input2LZOC<=passedInput(62 downto 0);
   LZOC_component: Fix2FP_0_63_S_11_52_LZOCS  -- pipelineDepth=5 maxInDelay=0
      port map ( clk  => clk,
                 rst  => rst,
                 Count => temporalExponent,
                 I => input2LZOC,
                 O => temporalFraction,
                 OZb => signSignal);
   ----------------Synchro barrier, entering cycle 5----------------
   MSB2Signal<=CONV_STD_LOGIC_VECTOR(62,11);
   zeroPadding4Exponent<=CONV_STD_LOGIC_VECTOR(0,5);
   valueExponent<= not (zeroPadding4Exponent & temporalExponent );
   exponentConversion: Fix2FP_0_63_S_11_52exponentConversion  -- pipelineDepth=0 maxInDelay=0
      port map ( clk  => clk,
                 rst  => rst,
                 Cin => '1',
                 R => partialConvertedExponent,
                 X => MSB2Signal,
                 Y => valueExponent);
   biassOfOnes<=CONV_STD_LOGIC_VECTOR(2047,10);
   biassSignal<='0' & biassOfOnes;
   biassSignalBit<='0' & biassSignal;
   partialConvertedExponentBit<= '0' & partialConvertedExponent;
   sign4OU<=partialConvertedExponent(10);
   exponentFinal: Fix2FP_0_63_S_11_52exponentFinal  -- pipelineDepth=0 maxInDelay=0
      port map ( clk  => clk,
                 rst  => rst,
                 Cin => '0',
                 R => convertedExponentBit,
                 X => partialConvertedExponentBit,
                 Y => biassSignalBit);
   convertedExponent<= convertedExponentBit(10 downto 0);
   underflowSignal<= '1' when (sign4OU='1' and convertedExponentBit(11 downto 10) = "01" ) else '0' ;
   overflowSignal<= '1' when (sign4OU='0' and convertedExponentBit(11 downto 10) = "10" ) else '0' ;
   ---------------- cycle 0----------------
   minusOne4ZD<=CONV_STD_LOGIC_VECTOR(-1,64);
   zeroD: Fix2FP_0_63_S_11_52zeroD  -- pipelineDepth=1 maxInDelay=0
      port map ( clk  => clk,
                 rst  => rst,
                 Cin => '0',
                 R => zeroDS,
                 X => passedInput,
                 Y => minusOne4ZD);
   ----------------Synchro barrier, entering cycle 1----------------
   zeroInput<= zeroDS(63) and not(signSignal_d1);
   ---------------- cycle 5----------------
   sign2vector<=(others => signSignal_d5);
   tempConvert<= sign2vector xor temporalFraction;
   tempConvert0<= '0' & tempConvert;
   tempPaddingAddSign<=(others=>'0');
   tempAddSign<=tempPaddingAddSign & signSignal_d5;
   fractionConverter: Fix2FP_0_63_S_11_52_fractionConvert  -- pipelineDepth=1 maxInDelay=0
      port map ( clk  => clk,
                 rst  => rst,
                 Cin => '0',
                 R => tempFractionResult,
                 X => tempConvert0,
                 Y => tempAddSign);
   ----------------Synchro barrier, entering cycle 6----------------
   correctingExponent<=tempFractionResult(64);
   fractionConverted<=tempFractionResult(62 downto 11);
   firstBitofRest<=tempFractionResult(10);
   lastBitOfFraction<=tempFractionResult(11);
   ---------------- cycle 6----------------
   minusOne<=CONV_STD_LOGIC_VECTOR(-1,10);
   fractionRemainder<= tempFractionResult(9 downto 0);
   oneSubstracter: Fix2FP_0_63_S_11_52_oneSubstracter  -- pipelineDepth=0 maxInDelay=0
      port map ( clk  => clk,
                 rst  => rst,
                 Cin => '0',
                 R => zeroFractionResult,
                 X => fractionRemainder,
                 Y => minusOne);
   zeroRemainder<= not( not (tempFractionResult(9)) and zeroFractionResult(9));
   ----------------Synchro barrier, entering cycle 7----------------
   outputOfMux3<=lastBitOfFraction_d1;
   with zeroRemainder_d1 select 
   outputOfMux2 <= outputOfMux3 when '0', '1' when others;
   with firstBitofRest_d1 select 
   outputOfMux1 <= outputOfMux2 when '1', '0' when others;
   possibleCorrector4Rounding<=CONV_STD_LOGIC_VECTOR(0,11) & correctingExponent_d1 & CONV_STD_LOGIC_VECTOR(0,52);
   concatenationForRounding<= '0' & convertedExponent_d2 & fractionConverted_d1;
   testC<= concatenationForRounding;
   testR<= possibleCorrector4Rounding;
   testM<= outputOfMux1;
   roundingAdder: Fix2FP_0_63_S_11_52roundingAdder  -- pipelineDepth=1 maxInDelay=0
      port map ( clk  => clk,
                 rst  => rst,
                 Cin => outputOfMux1,
                 R => roundedResult,
                 X => concatenationForRounding,
                 Y => possibleCorrector4Rounding);
   ----------------Synchro barrier, entering cycle 8----------------
   convertedExponentAfterRounding<= roundedResult(62 downto 52);
   convertedFractionAfterRounding<= roundedResult(51 downto 0);
   MSBSelection<= overflowSignal_d3 or roundedResult(63);
   LSBSelection<= not(underflowSignal_d3 and not(zeroInput_d7));
   Selection<= MSBSelection & LSBSelection when zeroInput_d7='0' else "00";
   specialBits <= Selection;
   O<= specialBits & signSignal_d8 & convertedExponentAfterRounding & convertedFractionAfterRounding;
end architecture;

--------------------------------------------------------------------------------
--                 FP2Fix_11_52_0_63_S_NTExponent_difference
--                         (IntAdder_11_f400_uid230)
-- This operator is part of the Infinite Virtual Library FloPoCoLib
-- All rights reserved 
-- Authors: Bogdan Pasca, Florent de Dinechin (2008-2010)
--------------------------------------------------------------------------------
-- Pipeline depth: 0 cycles

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library std;
use std.textio.all;
library work;

entity FP2Fix_11_52_0_63_S_NTExponent_difference is
   port ( clk, rst : in std_logic;
          X : in  std_logic_vector(10 downto 0);
          Y : in  std_logic_vector(10 downto 0);
          Cin : in std_logic;
          R : out  std_logic_vector(10 downto 0)   );
end entity;

architecture arch of FP2Fix_11_52_0_63_S_NTExponent_difference is
begin
   process(clk)
      begin
         if clk'event and clk = '1' then
         end if;
      end process;
   --Classical
    R <= X + Y + Cin;
end architecture;

--------------------------------------------------------------------------------
--                      LeftShifter_53_by_max_66_uid237
-- This operator is part of the Infinite Virtual Library FloPoCoLib
-- All rights reserved 
-- Authors: Bogdan Pasca, Florent de Dinechin (2008-2011)
--------------------------------------------------------------------------------
-- Pipeline depth: 1 cycles

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library std;
use std.textio.all;
library work;

entity LeftShifter_53_by_max_66_uid237 is
   port ( clk, rst : in std_logic;
          X : in  std_logic_vector(52 downto 0);
          S : in  std_logic_vector(6 downto 0);
          R : out  std_logic_vector(118 downto 0)   );
end entity;

architecture arch of LeftShifter_53_by_max_66_uid237 is
signal level0 :  std_logic_vector(52 downto 0);
signal ps, ps_d1 :  std_logic_vector(6 downto 0);
signal level1 :  std_logic_vector(53 downto 0);
signal level2 :  std_logic_vector(55 downto 0);
signal level3 :  std_logic_vector(59 downto 0);
signal level4, level4_d1 :  std_logic_vector(67 downto 0);
signal level5 :  std_logic_vector(83 downto 0);
signal level6 :  std_logic_vector(115 downto 0);
signal level7 :  std_logic_vector(179 downto 0);
begin
   process(clk)
      begin
         if clk'event and clk = '1' then
            ps_d1 <=  ps;
            level4_d1 <=  level4;
         end if;
      end process;
   level0<= X;
   ps<= S;
   level1<= level0 & (0 downto 0 => '0') when ps(0)= '1' else     (0 downto 0 => '0') & level0;
   level2<= level1 & (1 downto 0 => '0') when ps(1)= '1' else     (1 downto 0 => '0') & level1;
   level3<= level2 & (3 downto 0 => '0') when ps(2)= '1' else     (3 downto 0 => '0') & level2;
   level4<= level3 & (7 downto 0 => '0') when ps(3)= '1' else     (7 downto 0 => '0') & level3;
   ----------------Synchro barrier, entering cycle 1----------------
   level5<= level4_d1 & (15 downto 0 => '0') when ps_d1(4)= '1' else     (15 downto 0 => '0') & level4_d1;
   level6<= level5 & (31 downto 0 => '0') when ps_d1(5)= '1' else     (31 downto 0 => '0') & level5;
   level7<= level6 & (63 downto 0 => '0') when ps_d1(6)= '1' else     (63 downto 0 => '0') & level6;
   R <= level7(118 downto 0);
end architecture;

--------------------------------------------------------------------------------
--                       FP2Fix_11_52_0_63_S_NTMantSum
--                         (IntAdder_65_f400_uid240)
-- This operator is part of the Infinite Virtual Library FloPoCoLib
-- All rights reserved 
-- Authors: Bogdan Pasca, Florent de Dinechin (2008-2010)
--------------------------------------------------------------------------------
-- Pipeline depth: 1 cycles

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library std;
use std.textio.all;
library work;

entity FP2Fix_11_52_0_63_S_NTMantSum is
   port ( clk, rst : in std_logic;
          X : in  std_logic_vector(64 downto 0);
          Y : in  std_logic_vector(64 downto 0);
          Cin : in std_logic;
          R : out  std_logic_vector(64 downto 0)   );
end entity;

architecture arch of FP2Fix_11_52_0_63_S_NTMantSum is
signal s_sum_l0_idx0 :  std_logic_vector(42 downto 0);
signal s_sum_l0_idx1, s_sum_l0_idx1_d1 :  std_logic_vector(23 downto 0);
signal sum_l0_idx0, sum_l0_idx0_d1 :  std_logic_vector(41 downto 0);
signal c_l0_idx0, c_l0_idx0_d1 :  std_logic_vector(0 downto 0);
signal sum_l0_idx1 :  std_logic_vector(22 downto 0);
signal c_l0_idx1 :  std_logic_vector(0 downto 0);
signal s_sum_l1_idx1 :  std_logic_vector(23 downto 0);
signal sum_l1_idx1 :  std_logic_vector(22 downto 0);
signal c_l1_idx1 :  std_logic_vector(0 downto 0);
begin
   process(clk)
      begin
         if clk'event and clk = '1' then
            s_sum_l0_idx1_d1 <=  s_sum_l0_idx1;
            sum_l0_idx0_d1 <=  sum_l0_idx0;
            c_l0_idx0_d1 <=  c_l0_idx0;
         end if;
      end process;
   --Alternative
   s_sum_l0_idx0 <= ( "0" & X(41 downto 0)) + ( "0" & Y(41 downto 0)) + Cin;
   s_sum_l0_idx1 <= ( "0" & X(64 downto 42)) + ( "0" & Y(64 downto 42));
   sum_l0_idx0 <= s_sum_l0_idx0(41 downto 0);
   c_l0_idx0 <= s_sum_l0_idx0(42 downto 42);
   sum_l0_idx1 <= s_sum_l0_idx1(22 downto 0);
   c_l0_idx1 <= s_sum_l0_idx1(23 downto 23);
   ----------------Synchro barrier, entering cycle 1----------------
   s_sum_l1_idx1 <=  s_sum_l0_idx1_d1 + c_l0_idx0_d1(0 downto 0);
   sum_l1_idx1 <= s_sum_l1_idx1(22 downto 0);
   c_l1_idx1 <= s_sum_l1_idx1(23 downto 23);
   R <= sum_l1_idx1(22 downto 0) & sum_l0_idx0_d1(41 downto 0);
end architecture;

--------------------------------------------------------------------------------
--                           FP2Fix_11_52_0_63_S_NT
-- This operator is part of the Infinite Virtual Library FloPoCoLib
-- All rights reserved 
-- Authors: Fabrizio Ferrandi (2012)
--------------------------------------------------------------------------------
-- Pipeline depth: 5 cycles

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library std;
use std.textio.all;
library work;

entity FP2Fix_11_52_0_63_S_NT is
   port ( clk, rst : in std_logic;
          I : in  std_logic_vector(11+52+2 downto 0);
          O : out  std_logic_vector(63 downto 0)   );
end entity;

architecture arch of FP2Fix_11_52_0_63_S_NT is
   component FP2Fix_11_52_0_63_S_NTExponent_difference is
      port ( clk, rst : in std_logic;
             X : in  std_logic_vector(10 downto 0);
             Y : in  std_logic_vector(10 downto 0);
             Cin : in std_logic;
             R : out  std_logic_vector(10 downto 0)   );
   end component;

   component FP2Fix_11_52_0_63_S_NTMantSum is
      port ( clk, rst : in std_logic;
             X : in  std_logic_vector(64 downto 0);
             Y : in  std_logic_vector(64 downto 0);
             Cin : in std_logic;
             R : out  std_logic_vector(64 downto 0)   );
   end component;

   component LeftShifter_53_by_max_66_uid237 is
      port ( clk, rst : in std_logic;
             X : in  std_logic_vector(52 downto 0);
             S : in  std_logic_vector(6 downto 0);
             R : out  std_logic_vector(118 downto 0)   );
   end component;

signal eA0 :  std_logic_vector(10 downto 0);
signal fA0, fA0_d1 :  std_logic_vector(52 downto 0);
signal bias :  std_logic_vector(10 downto 0);
signal eA1, eA1_d1 :  std_logic_vector(10 downto 0);
signal shiftedby :  std_logic_vector(6 downto 0);
signal fA1 :  std_logic_vector(118 downto 0);
signal fA2a :  std_logic_vector(64 downto 0);
signal notallzero : std_logic;
signal round : std_logic;
signal fA2b :  std_logic_vector(64 downto 0);
signal fA3, fA3_d1, fA3_d2 :  std_logic_vector(64 downto 0);
signal fA3b, fA3b_d1 :  std_logic_vector(64 downto 0);
signal fA4 :  std_logic_vector(63 downto 0);
signal overFl0 : std_logic;
signal overFl1 : std_logic;
signal eTest : std_logic;
signal I_d1, I_d2, I_d3, I_d4, I_d5 :  std_logic_vector(11+52+2 downto 0);
begin
   process(clk)
      begin
         if clk'event and clk = '1' then
            fA0_d1 <=  fA0;
            eA1_d1 <=  eA1;
            fA3_d1 <=  fA3;
            fA3_d2 <=  fA3_d1;
            fA3b_d1 <=  fA3b;
            I_d1 <=  I;
            I_d2 <=  I_d1;
            I_d3 <=  I_d2;
            I_d4 <=  I_d3;
            I_d5 <=  I_d4;
         end if;
      end process;
   eA0 <= I(62 downto 52);
   fA0 <= "1" & I(51 downto 0);
   bias <= not conv_std_logic_vector(1022, 11);
   Exponent_difference: FP2Fix_11_52_0_63_S_NTExponent_difference  -- pipelineDepth=0 maxInDelay=0
      port map ( clk  => clk,
                 rst  => rst,
                 Cin => '1',
                 R => eA1,
                 X => bias,
                 Y => eA0);
   ---------------- cycle 0----------------
   ----------------Synchro barrier, entering cycle 1----------------
   shiftedby <= eA1_d1(6 downto 0) when eA1_d1(10) = '0' else (6 downto 0 => '0');
   FXP_shifter: LeftShifter_53_by_max_66_uid237  -- pipelineDepth=1 maxInDelay=0
      port map ( clk  => clk,
                 rst  => rst,
                 R => fA1,
                 S => shiftedby,
                 X => fA0_d1);
   ----------------Synchro barrier, entering cycle 2----------------
   fA2a<= '0' & fA1(116 downto 53);
   notallzero <= '0' when fA1(51 downto 0) = (51 downto 0 => '0') else '1';
   round <= (fA1(52) and I_d2(63)) or (fA1(52) and notallzero and not I_d2(63));
   fA2b<= '0' & (63 downto 1 => '0') & round;
   MantSum: FP2Fix_11_52_0_63_S_NTMantSum  -- pipelineDepth=1 maxInDelay=0
      port map ( clk  => clk,
                 rst  => rst,
                 Cin => '0',
                 R => fA3,
                 X => fA2a,
                 Y => fA2b);
   ---------------- cycle 3----------------
   ----------------Synchro barrier, entering cycle 4----------------
   fA3b<= -signed(fA3_d1);
   ----------------Synchro barrier, entering cycle 5----------------
   fA4<= fA3_d2(63 downto 0) when I_d5(63) = '0' else fA3b_d1(63 downto 0);
   overFl0<= '1' when I_d5(62 downto 52) > conv_std_logic_vector(1086,11) else I_d5(65);
   overFl1 <= fA3_d2(64);
   eTest <= (overFl0 or overFl1);
   O <= fA4 when eTest = '0' else
      I_d5(63) & (62 downto 0 => not I_d5(63));
end architecture;

--------------------------------------------------------------------------------
--                          InputIEEE_11_52_to_11_52
-- This operator is part of the Infinite Virtual Library FloPoCoLib
-- All rights reserved 
-- Authors: Florent de Dinechin (2008)
--------------------------------------------------------------------------------
-- Pipeline depth: 0 cycles

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library std;
use std.textio.all;
library work;

entity InputIEEE_11_52_to_11_52 is
   port ( clk, rst : in std_logic;
          X : in  std_logic_vector(63 downto 0);
          R : out  std_logic_vector(11+52+2 downto 0)   );
end entity;

architecture arch of InputIEEE_11_52_to_11_52 is
signal expX :  std_logic_vector(10 downto 0);
signal fracX :  std_logic_vector(51 downto 0);
signal sX : std_logic;
signal expZero : std_logic;
signal expInfty : std_logic;
signal fracZero : std_logic;
signal reprSubNormal : std_logic;
signal sfracX :  std_logic_vector(51 downto 0);
signal fracR :  std_logic_vector(51 downto 0);
signal expR :  std_logic_vector(10 downto 0);
signal infinity : std_logic;
signal zero : std_logic;
signal NaN : std_logic;
signal exnR :  std_logic_vector(1 downto 0);
begin
   process(clk)
      begin
         if clk'event and clk = '1' then
         end if;
      end process;
   expX  <= X(62 downto 52);
   fracX  <= X(51 downto 0);
   sX  <= X(63);
   expZero  <= '1' when expX = (10 downto 0 => '0') else '0';
   expInfty  <= '1' when expX = (10 downto 0 => '1') else '0';
   fracZero <= '1' when fracX = (51 downto 0 => '0') else '0';
   reprSubNormal <= fracX(51);
   -- since we have one more exponent value than IEEE (field 0...0, value emin-1),
   -- we can represent subnormal numbers whose mantissa field begins with a 1
   sfracX <= fracX(50 downto 0) & '0' when (expZero='1' and reprSubNormal='1')    else fracX;
   fracR <= sfracX;
   -- copy exponent. This will be OK even for subnormals, zero and infty since in such cases the exn bits will prevail
   expR <= expX;
   infinity <= expInfty and fracZero;
   zero <= expZero and not reprSubNormal;
   NaN <= expInfty and not fracZero;
   exnR <= 
           "00" when zero='1' 
      else "10" when infinity='1' 
      else "11" when NaN='1' 
      else "01" ;  -- normal number
   R <= exnR & sX & expR & fracR; 
end architecture;

--------------------------------------------------------------------------------
--                         OutputIEEE_11_52_to_11_52
-- This operator is part of the Infinite Virtual Library FloPoCoLib
-- All rights reserved 
-- Authors: F. Ferrandi  (2009-2012)
--------------------------------------------------------------------------------
-- Pipeline depth: 0 cycles

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library std;
use std.textio.all;
library work;

entity OutputIEEE_11_52_to_11_52 is
   port ( clk, rst : in std_logic;
          X : in  std_logic_vector(11+52+2 downto 0);
          R : out  std_logic_vector(63 downto 0)   );
end entity;

architecture arch of OutputIEEE_11_52_to_11_52 is
signal expX :  std_logic_vector(10 downto 0);
signal fracX :  std_logic_vector(51 downto 0);
signal exnX :  std_logic_vector(1 downto 0);
signal sX : std_logic;
signal expZero : std_logic;
signal sfracX :  std_logic_vector(51 downto 0);
signal fracR :  std_logic_vector(51 downto 0);
signal expR :  std_logic_vector(10 downto 0);
begin
   process(clk)
      begin
         if clk'event and clk = '1' then
         end if;
      end process;
   expX  <= X(62 downto 52);
   fracX  <= X(51 downto 0);
   exnX  <= X(65 downto 64);
   sX  <= X(63) when (exnX = "01" or exnX = "10" or exnX = "00") else '0';
   expZero  <= '1' when expX = (10 downto 0 => '0') else '0';
   -- since we have one more exponent value than IEEE (field 0...0, value emin-1),
   -- we can represent subnormal numbers whose mantissa field begins with a 1
   sfracX <= 
      (51 downto 0 => '0') when (exnX = "00") else
      '1' & fracX(51 downto 1) when (expZero = '1' and exnX = "01") else
      fracX when (exnX = "01") else 
      (51 downto 1 => '0') & exnX(0);
   fracR <= sfracX;
   expR <=  
      (10 downto 0 => '0') when (exnX = "00") else
      expX when (exnX = "01") else 
      (10 downto 0 => '1');
   R <= sX & expR & fracR; 
end architecture;

--------------------------------------------------------------------------------
--                                 FPDiv_8_23
-- This operator is part of the Infinite Virtual Library FloPoCoLib
-- All rights reserved 
-- Authors: 
--------------------------------------------------------------------------------
-- Pipeline depth: 17 cycles

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library std;
use std.textio.all;
library work;

entity FPDiv_8_23 is
   port ( clk, rst, ce : in std_logic;
          X : in  std_logic_vector(8+23+2 downto 0);
          Y : in  std_logic_vector(8+23+2 downto 0);
          R : out  std_logic_vector(8+23+2 downto 0)   );
end entity;

architecture arch of FPDiv_8_23 is
signal fX :  std_logic_vector(23 downto 0);
signal fY, fY_d1, fY_d2, fY_d3, fY_d4, fY_d5, fY_d6, fY_d7, fY_d8, fY_d9, fY_d10, fY_d11, fY_d12, fY_d13, fY_d14 :  std_logic_vector(23 downto 0);
signal expR0, expR0_d1, expR0_d2, expR0_d3, expR0_d4, expR0_d5, expR0_d6, expR0_d7, expR0_d8, expR0_d9, expR0_d10, expR0_d11, expR0_d12, expR0_d13, expR0_d14, expR0_d15, expR0_d16 :  std_logic_vector(9 downto 0);
signal sR, sR_d1, sR_d2, sR_d3, sR_d4, sR_d5, sR_d6, sR_d7, sR_d8, sR_d9, sR_d10, sR_d11, sR_d12, sR_d13, sR_d14, sR_d15, sR_d16, sR_d17 : std_logic;
signal exnXY :  std_logic_vector(3 downto 0);
signal exnR0, exnR0_d1, exnR0_d2, exnR0_d3, exnR0_d4, exnR0_d5, exnR0_d6, exnR0_d7, exnR0_d8, exnR0_d9, exnR0_d10, exnR0_d11, exnR0_d12, exnR0_d13, exnR0_d14, exnR0_d15, exnR0_d16, exnR0_d17 :  std_logic_vector(1 downto 0);
signal fYTimes3, fYTimes3_d1, fYTimes3_d2, fYTimes3_d3, fYTimes3_d4, fYTimes3_d5, fYTimes3_d6, fYTimes3_d7, fYTimes3_d8, fYTimes3_d9, fYTimes3_d10, fYTimes3_d11, fYTimes3_d12, fYTimes3_d13, fYTimes3_d14 :  std_logic_vector(25 downto 0);
signal w13, w13_d1, w13_d2 :  std_logic_vector(25 downto 0);
signal sel13 :  std_logic_vector(4 downto 0);
signal q13, q13_d1, q13_d2, q13_d3, q13_d4, q13_d5, q13_d6, q13_d7, q13_d8, q13_d9, q13_d10, q13_d11, q13_d12, q13_d13 :  std_logic_vector(2 downto 0);
signal q13D :  std_logic_vector(26 downto 0);
signal w13pad :  std_logic_vector(26 downto 0);
signal w12full :  std_logic_vector(26 downto 0);
signal w12, w12_d1 :  std_logic_vector(25 downto 0);
signal sel12 :  std_logic_vector(4 downto 0);
signal q12, q12_d1, q12_d2, q12_d3, q12_d4, q12_d5, q12_d6, q12_d7, q12_d8, q12_d9, q12_d10, q12_d11, q12_d12 :  std_logic_vector(2 downto 0);
signal q12D :  std_logic_vector(26 downto 0);
signal w12pad :  std_logic_vector(26 downto 0);
signal w11full :  std_logic_vector(26 downto 0);
signal w11, w11_d1 :  std_logic_vector(25 downto 0);
signal sel11 :  std_logic_vector(4 downto 0);
signal q11, q11_d1, q11_d2, q11_d3, q11_d4, q11_d5, q11_d6, q11_d7, q11_d8, q11_d9, q11_d10, q11_d11 :  std_logic_vector(2 downto 0);
signal q11D :  std_logic_vector(26 downto 0);
signal w11pad :  std_logic_vector(26 downto 0);
signal w10full :  std_logic_vector(26 downto 0);
signal w10, w10_d1 :  std_logic_vector(25 downto 0);
signal sel10 :  std_logic_vector(4 downto 0);
signal q10, q10_d1, q10_d2, q10_d3, q10_d4, q10_d5, q10_d6, q10_d7, q10_d8, q10_d9, q10_d10 :  std_logic_vector(2 downto 0);
signal q10D :  std_logic_vector(26 downto 0);
signal w10pad :  std_logic_vector(26 downto 0);
signal w9full :  std_logic_vector(26 downto 0);
signal w9, w9_d1 :  std_logic_vector(25 downto 0);
signal sel9 :  std_logic_vector(4 downto 0);
signal q9, q9_d1, q9_d2, q9_d3, q9_d4, q9_d5, q9_d6, q9_d7, q9_d8, q9_d9 :  std_logic_vector(2 downto 0);
signal q9D :  std_logic_vector(26 downto 0);
signal w9pad :  std_logic_vector(26 downto 0);
signal w8full :  std_logic_vector(26 downto 0);
signal w8, w8_d1 :  std_logic_vector(25 downto 0);
signal sel8 :  std_logic_vector(4 downto 0);
signal q8, q8_d1, q8_d2, q8_d3, q8_d4, q8_d5, q8_d6, q8_d7, q8_d8 :  std_logic_vector(2 downto 0);
signal q8D :  std_logic_vector(26 downto 0);
signal w8pad :  std_logic_vector(26 downto 0);
signal w7full :  std_logic_vector(26 downto 0);
signal w7, w7_d1 :  std_logic_vector(25 downto 0);
signal sel7 :  std_logic_vector(4 downto 0);
signal q7, q7_d1, q7_d2, q7_d3, q7_d4, q7_d5, q7_d6, q7_d7 :  std_logic_vector(2 downto 0);
signal q7D :  std_logic_vector(26 downto 0);
signal w7pad :  std_logic_vector(26 downto 0);
signal w6full :  std_logic_vector(26 downto 0);
signal w6, w6_d1 :  std_logic_vector(25 downto 0);
signal sel6 :  std_logic_vector(4 downto 0);
signal q6, q6_d1, q6_d2, q6_d3, q6_d4, q6_d5, q6_d6 :  std_logic_vector(2 downto 0);
signal q6D :  std_logic_vector(26 downto 0);
signal w6pad :  std_logic_vector(26 downto 0);
signal w5full :  std_logic_vector(26 downto 0);
signal w5, w5_d1 :  std_logic_vector(25 downto 0);
signal sel5 :  std_logic_vector(4 downto 0);
signal q5, q5_d1, q5_d2, q5_d3, q5_d4, q5_d5 :  std_logic_vector(2 downto 0);
signal q5D :  std_logic_vector(26 downto 0);
signal w5pad :  std_logic_vector(26 downto 0);
signal w4full :  std_logic_vector(26 downto 0);
signal w4, w4_d1 :  std_logic_vector(25 downto 0);
signal sel4 :  std_logic_vector(4 downto 0);
signal q4, q4_d1, q4_d2, q4_d3, q4_d4 :  std_logic_vector(2 downto 0);
signal q4D :  std_logic_vector(26 downto 0);
signal w4pad :  std_logic_vector(26 downto 0);
signal w3full :  std_logic_vector(26 downto 0);
signal w3, w3_d1 :  std_logic_vector(25 downto 0);
signal sel3 :  std_logic_vector(4 downto 0);
signal q3, q3_d1, q3_d2, q3_d3 :  std_logic_vector(2 downto 0);
signal q3D :  std_logic_vector(26 downto 0);
signal w3pad :  std_logic_vector(26 downto 0);
signal w2full :  std_logic_vector(26 downto 0);
signal w2, w2_d1 :  std_logic_vector(25 downto 0);
signal sel2 :  std_logic_vector(4 downto 0);
signal q2, q2_d1, q2_d2 :  std_logic_vector(2 downto 0);
signal q2D :  std_logic_vector(26 downto 0);
signal w2pad :  std_logic_vector(26 downto 0);
signal w1full :  std_logic_vector(26 downto 0);
signal w1, w1_d1 :  std_logic_vector(25 downto 0);
signal sel1 :  std_logic_vector(4 downto 0);
signal q1, q1_d1 :  std_logic_vector(2 downto 0);
signal q1D :  std_logic_vector(26 downto 0);
signal w1pad :  std_logic_vector(26 downto 0);
signal w0full :  std_logic_vector(26 downto 0);
signal w0, w0_d1 :  std_logic_vector(25 downto 0);
signal q0 :  std_logic_vector(2 downto 0);
signal qP13 :  std_logic_vector(1 downto 0);
signal qM13 :  std_logic_vector(1 downto 0);
signal qP12 :  std_logic_vector(1 downto 0);
signal qM12 :  std_logic_vector(1 downto 0);
signal qP11 :  std_logic_vector(1 downto 0);
signal qM11 :  std_logic_vector(1 downto 0);
signal qP10 :  std_logic_vector(1 downto 0);
signal qM10 :  std_logic_vector(1 downto 0);
signal qP9 :  std_logic_vector(1 downto 0);
signal qM9 :  std_logic_vector(1 downto 0);
signal qP8 :  std_logic_vector(1 downto 0);
signal qM8 :  std_logic_vector(1 downto 0);
signal qP7 :  std_logic_vector(1 downto 0);
signal qM7 :  std_logic_vector(1 downto 0);
signal qP6 :  std_logic_vector(1 downto 0);
signal qM6 :  std_logic_vector(1 downto 0);
signal qP5 :  std_logic_vector(1 downto 0);
signal qM5 :  std_logic_vector(1 downto 0);
signal qP4 :  std_logic_vector(1 downto 0);
signal qM4 :  std_logic_vector(1 downto 0);
signal qP3 :  std_logic_vector(1 downto 0);
signal qM3 :  std_logic_vector(1 downto 0);
signal qP2 :  std_logic_vector(1 downto 0);
signal qM2 :  std_logic_vector(1 downto 0);
signal qP1 :  std_logic_vector(1 downto 0);
signal qM1 :  std_logic_vector(1 downto 0);
signal qP0 :  std_logic_vector(1 downto 0);
signal qM0 :  std_logic_vector(1 downto 0);
signal qP :  std_logic_vector(27 downto 0);
signal qM :  std_logic_vector(27 downto 0);
signal fR0, fR0_d1 :  std_logic_vector(27 downto 0);
signal fR :  std_logic_vector(26 downto 0);
signal fRn1, fRn1_d1 :  std_logic_vector(24 downto 0);
signal expR1, expR1_d1 :  std_logic_vector(9 downto 0);
signal round, round_d1 : std_logic;
signal expfrac :  std_logic_vector(32 downto 0);
signal expfracR :  std_logic_vector(32 downto 0);
signal exnR :  std_logic_vector(1 downto 0);
signal exnRfinal :  std_logic_vector(1 downto 0);
begin
   process(clk)
      begin
         if clk'event and clk = '1' then
            if ce = '1' then
               fY_d1 <=  fY;
               fY_d2 <=  fY_d1;
               fY_d3 <=  fY_d2;
               fY_d4 <=  fY_d3;
               fY_d5 <=  fY_d4;
               fY_d6 <=  fY_d5;
               fY_d7 <=  fY_d6;
               fY_d8 <=  fY_d7;
               fY_d9 <=  fY_d8;
               fY_d10 <=  fY_d9;
               fY_d11 <=  fY_d10;
               fY_d12 <=  fY_d11;
               fY_d13 <=  fY_d12;
               fY_d14 <=  fY_d13;
               expR0_d1 <=  expR0;
               expR0_d2 <=  expR0_d1;
               expR0_d3 <=  expR0_d2;
               expR0_d4 <=  expR0_d3;
               expR0_d5 <=  expR0_d4;
               expR0_d6 <=  expR0_d5;
               expR0_d7 <=  expR0_d6;
               expR0_d8 <=  expR0_d7;
               expR0_d9 <=  expR0_d8;
               expR0_d10 <=  expR0_d9;
               expR0_d11 <=  expR0_d10;
               expR0_d12 <=  expR0_d11;
               expR0_d13 <=  expR0_d12;
               expR0_d14 <=  expR0_d13;
               expR0_d15 <=  expR0_d14;
               expR0_d16 <=  expR0_d15;
               sR_d1 <=  sR;
               sR_d2 <=  sR_d1;
               sR_d3 <=  sR_d2;
               sR_d4 <=  sR_d3;
               sR_d5 <=  sR_d4;
               sR_d6 <=  sR_d5;
               sR_d7 <=  sR_d6;
               sR_d8 <=  sR_d7;
               sR_d9 <=  sR_d8;
               sR_d10 <=  sR_d9;
               sR_d11 <=  sR_d10;
               sR_d12 <=  sR_d11;
               sR_d13 <=  sR_d12;
               sR_d14 <=  sR_d13;
               sR_d15 <=  sR_d14;
               sR_d16 <=  sR_d15;
               sR_d17 <=  sR_d16;
               exnR0_d1 <=  exnR0;
               exnR0_d2 <=  exnR0_d1;
               exnR0_d3 <=  exnR0_d2;
               exnR0_d4 <=  exnR0_d3;
               exnR0_d5 <=  exnR0_d4;
               exnR0_d6 <=  exnR0_d5;
               exnR0_d7 <=  exnR0_d6;
               exnR0_d8 <=  exnR0_d7;
               exnR0_d9 <=  exnR0_d8;
               exnR0_d10 <=  exnR0_d9;
               exnR0_d11 <=  exnR0_d10;
               exnR0_d12 <=  exnR0_d11;
               exnR0_d13 <=  exnR0_d12;
               exnR0_d14 <=  exnR0_d13;
               exnR0_d15 <=  exnR0_d14;
               exnR0_d16 <=  exnR0_d15;
               exnR0_d17 <=  exnR0_d16;
               fYTimes3_d1 <=  fYTimes3;
               fYTimes3_d2 <=  fYTimes3_d1;
               fYTimes3_d3 <=  fYTimes3_d2;
               fYTimes3_d4 <=  fYTimes3_d3;
               fYTimes3_d5 <=  fYTimes3_d4;
               fYTimes3_d6 <=  fYTimes3_d5;
               fYTimes3_d7 <=  fYTimes3_d6;
               fYTimes3_d8 <=  fYTimes3_d7;
               fYTimes3_d9 <=  fYTimes3_d8;
               fYTimes3_d10 <=  fYTimes3_d9;
               fYTimes3_d11 <=  fYTimes3_d10;
               fYTimes3_d12 <=  fYTimes3_d11;
               fYTimes3_d13 <=  fYTimes3_d12;
               fYTimes3_d14 <=  fYTimes3_d13;
               w13_d1 <=  w13;
               w13_d2 <=  w13_d1;
               q13_d1 <=  q13;
               q13_d2 <=  q13_d1;
               q13_d3 <=  q13_d2;
               q13_d4 <=  q13_d3;
               q13_d5 <=  q13_d4;
               q13_d6 <=  q13_d5;
               q13_d7 <=  q13_d6;
               q13_d8 <=  q13_d7;
               q13_d9 <=  q13_d8;
               q13_d10 <=  q13_d9;
               q13_d11 <=  q13_d10;
               q13_d12 <=  q13_d11;
               q13_d13 <=  q13_d12;
               w12_d1 <=  w12;
               q12_d1 <=  q12;
               q12_d2 <=  q12_d1;
               q12_d3 <=  q12_d2;
               q12_d4 <=  q12_d3;
               q12_d5 <=  q12_d4;
               q12_d6 <=  q12_d5;
               q12_d7 <=  q12_d6;
               q12_d8 <=  q12_d7;
               q12_d9 <=  q12_d8;
               q12_d10 <=  q12_d9;
               q12_d11 <=  q12_d10;
               q12_d12 <=  q12_d11;
               w11_d1 <=  w11;
               q11_d1 <=  q11;
               q11_d2 <=  q11_d1;
               q11_d3 <=  q11_d2;
               q11_d4 <=  q11_d3;
               q11_d5 <=  q11_d4;
               q11_d6 <=  q11_d5;
               q11_d7 <=  q11_d6;
               q11_d8 <=  q11_d7;
               q11_d9 <=  q11_d8;
               q11_d10 <=  q11_d9;
               q11_d11 <=  q11_d10;
               w10_d1 <=  w10;
               q10_d1 <=  q10;
               q10_d2 <=  q10_d1;
               q10_d3 <=  q10_d2;
               q10_d4 <=  q10_d3;
               q10_d5 <=  q10_d4;
               q10_d6 <=  q10_d5;
               q10_d7 <=  q10_d6;
               q10_d8 <=  q10_d7;
               q10_d9 <=  q10_d8;
               q10_d10 <=  q10_d9;
               w9_d1 <=  w9;
               q9_d1 <=  q9;
               q9_d2 <=  q9_d1;
               q9_d3 <=  q9_d2;
               q9_d4 <=  q9_d3;
               q9_d5 <=  q9_d4;
               q9_d6 <=  q9_d5;
               q9_d7 <=  q9_d6;
               q9_d8 <=  q9_d7;
               q9_d9 <=  q9_d8;
               w8_d1 <=  w8;
               q8_d1 <=  q8;
               q8_d2 <=  q8_d1;
               q8_d3 <=  q8_d2;
               q8_d4 <=  q8_d3;
               q8_d5 <=  q8_d4;
               q8_d6 <=  q8_d5;
               q8_d7 <=  q8_d6;
               q8_d8 <=  q8_d7;
               w7_d1 <=  w7;
               q7_d1 <=  q7;
               q7_d2 <=  q7_d1;
               q7_d3 <=  q7_d2;
               q7_d4 <=  q7_d3;
               q7_d5 <=  q7_d4;
               q7_d6 <=  q7_d5;
               q7_d7 <=  q7_d6;
               w6_d1 <=  w6;
               q6_d1 <=  q6;
               q6_d2 <=  q6_d1;
               q6_d3 <=  q6_d2;
               q6_d4 <=  q6_d3;
               q6_d5 <=  q6_d4;
               q6_d6 <=  q6_d5;
               w5_d1 <=  w5;
               q5_d1 <=  q5;
               q5_d2 <=  q5_d1;
               q5_d3 <=  q5_d2;
               q5_d4 <=  q5_d3;
               q5_d5 <=  q5_d4;
               w4_d1 <=  w4;
               q4_d1 <=  q4;
               q4_d2 <=  q4_d1;
               q4_d3 <=  q4_d2;
               q4_d4 <=  q4_d3;
               w3_d1 <=  w3;
               q3_d1 <=  q3;
               q3_d2 <=  q3_d1;
               q3_d3 <=  q3_d2;
               w2_d1 <=  w2;
               q2_d1 <=  q2;
               q2_d2 <=  q2_d1;
               w1_d1 <=  w1;
               q1_d1 <=  q1;
               w0_d1 <=  w0;
               fR0_d1 <=  fR0;
               fRn1_d1 <=  fRn1;
               expR1_d1 <=  expR1;
               round_d1 <=  round;
            end if;
         end if;
      end process;
   fX <= "1" & X(22 downto 0);
   fY <= "1" & Y(22 downto 0);
   -- exponent difference, sign and exception combination computed early, to have less bits to pipeline
   expR0 <= ("00" & X(30 downto 23)) - ("00" & Y(30 downto 23));
   sR <= X(31) xor Y(31);
   -- early exception handling 
   exnXY <= X(33 downto 32) & Y(33 downto 32);
   with exnXY select
      exnR0 <= 
         "01"  when "0101",                   -- normal
         "00"  when "0001" | "0010" | "0110", -- zero
         "10"  when "0100" | "1000" | "1001", -- overflow
         "11"  when others;                   -- NaN
    -- compute 3Y
   fYTimes3 <= ("00" & fY) + ("0" & fY & "0");
   w13 <=  "00" & fX;
   ----------------Synchro barrier, entering cycle 1----------------
   ----------------Synchro barrier, entering cycle 2----------------
   sel13 <= w13_d2(25 downto 22) & fY_d2(22);
   with sel13 select
   q13 <= 
      "001" when "00010" | "00011",
      "010" when "00100" | "00101" | "00111",
      "011" when "00110" | "01000" | "01001" | "01010" | "01011" | "01101" | "01111",
      "101" when "11000" | "10110" | "10111" | "10100" | "10101" | "10011" | "10001",
      "110" when "11010" | "11011" | "11001",
      "111" when "11100" | "11101",
      "000" when others;

   with q13 select
      q13D <= 
         "000" & fY_d2            when "001" | "111",
         "00" & fY_d2 & "0"     when "010" | "110",
         "0" & fYTimes3_d2             when "011" | "101",
         (26 downto 0 => '0') when others;

   w13pad <= w13_d2 & "0";
   with q13(2) select
   w12full<= w13pad - q13D when '0',
         w13pad + q13D when others;

   w12 <= w12full(24 downto 0) & "0";
   ----------------Synchro barrier, entering cycle 3----------------
   sel12 <= w12_d1(25 downto 22) & fY_d3(22);
   with sel12 select
   q12 <= 
      "001" when "00010" | "00011",
      "010" when "00100" | "00101" | "00111",
      "011" when "00110" | "01000" | "01001" | "01010" | "01011" | "01101" | "01111",
      "101" when "11000" | "10110" | "10111" | "10100" | "10101" | "10011" | "10001",
      "110" when "11010" | "11011" | "11001",
      "111" when "11100" | "11101",
      "000" when others;

   with q12 select
      q12D <= 
         "000" & fY_d3            when "001" | "111",
         "00" & fY_d3 & "0"     when "010" | "110",
         "0" & fYTimes3_d3             when "011" | "101",
         (26 downto 0 => '0') when others;

   w12pad <= w12_d1 & "0";
   with q12(2) select
   w11full<= w12pad - q12D when '0',
         w12pad + q12D when others;

   w11 <= w11full(24 downto 0) & "0";
   ----------------Synchro barrier, entering cycle 4----------------
   sel11 <= w11_d1(25 downto 22) & fY_d4(22);
   with sel11 select
   q11 <= 
      "001" when "00010" | "00011",
      "010" when "00100" | "00101" | "00111",
      "011" when "00110" | "01000" | "01001" | "01010" | "01011" | "01101" | "01111",
      "101" when "11000" | "10110" | "10111" | "10100" | "10101" | "10011" | "10001",
      "110" when "11010" | "11011" | "11001",
      "111" when "11100" | "11101",
      "000" when others;

   with q11 select
      q11D <= 
         "000" & fY_d4            when "001" | "111",
         "00" & fY_d4 & "0"     when "010" | "110",
         "0" & fYTimes3_d4             when "011" | "101",
         (26 downto 0 => '0') when others;

   w11pad <= w11_d1 & "0";
   with q11(2) select
   w10full<= w11pad - q11D when '0',
         w11pad + q11D when others;

   w10 <= w10full(24 downto 0) & "0";
   ----------------Synchro barrier, entering cycle 5----------------
   sel10 <= w10_d1(25 downto 22) & fY_d5(22);
   with sel10 select
   q10 <= 
      "001" when "00010" | "00011",
      "010" when "00100" | "00101" | "00111",
      "011" when "00110" | "01000" | "01001" | "01010" | "01011" | "01101" | "01111",
      "101" when "11000" | "10110" | "10111" | "10100" | "10101" | "10011" | "10001",
      "110" when "11010" | "11011" | "11001",
      "111" when "11100" | "11101",
      "000" when others;

   with q10 select
      q10D <= 
         "000" & fY_d5            when "001" | "111",
         "00" & fY_d5 & "0"     when "010" | "110",
         "0" & fYTimes3_d5             when "011" | "101",
         (26 downto 0 => '0') when others;

   w10pad <= w10_d1 & "0";
   with q10(2) select
   w9full<= w10pad - q10D when '0',
         w10pad + q10D when others;

   w9 <= w9full(24 downto 0) & "0";
   ----------------Synchro barrier, entering cycle 6----------------
   sel9 <= w9_d1(25 downto 22) & fY_d6(22);
   with sel9 select
   q9 <= 
      "001" when "00010" | "00011",
      "010" when "00100" | "00101" | "00111",
      "011" when "00110" | "01000" | "01001" | "01010" | "01011" | "01101" | "01111",
      "101" when "11000" | "10110" | "10111" | "10100" | "10101" | "10011" | "10001",
      "110" when "11010" | "11011" | "11001",
      "111" when "11100" | "11101",
      "000" when others;

   with q9 select
      q9D <= 
         "000" & fY_d6            when "001" | "111",
         "00" & fY_d6 & "0"     when "010" | "110",
         "0" & fYTimes3_d6             when "011" | "101",
         (26 downto 0 => '0') when others;

   w9pad <= w9_d1 & "0";
   with q9(2) select
   w8full<= w9pad - q9D when '0',
         w9pad + q9D when others;

   w8 <= w8full(24 downto 0) & "0";
   ----------------Synchro barrier, entering cycle 7----------------
   sel8 <= w8_d1(25 downto 22) & fY_d7(22);
   with sel8 select
   q8 <= 
      "001" when "00010" | "00011",
      "010" when "00100" | "00101" | "00111",
      "011" when "00110" | "01000" | "01001" | "01010" | "01011" | "01101" | "01111",
      "101" when "11000" | "10110" | "10111" | "10100" | "10101" | "10011" | "10001",
      "110" when "11010" | "11011" | "11001",
      "111" when "11100" | "11101",
      "000" when others;

   with q8 select
      q8D <= 
         "000" & fY_d7            when "001" | "111",
         "00" & fY_d7 & "0"     when "010" | "110",
         "0" & fYTimes3_d7             when "011" | "101",
         (26 downto 0 => '0') when others;

   w8pad <= w8_d1 & "0";
   with q8(2) select
   w7full<= w8pad - q8D when '0',
         w8pad + q8D when others;

   w7 <= w7full(24 downto 0) & "0";
   ----------------Synchro barrier, entering cycle 8----------------
   sel7 <= w7_d1(25 downto 22) & fY_d8(22);
   with sel7 select
   q7 <= 
      "001" when "00010" | "00011",
      "010" when "00100" | "00101" | "00111",
      "011" when "00110" | "01000" | "01001" | "01010" | "01011" | "01101" | "01111",
      "101" when "11000" | "10110" | "10111" | "10100" | "10101" | "10011" | "10001",
      "110" when "11010" | "11011" | "11001",
      "111" when "11100" | "11101",
      "000" when others;

   with q7 select
      q7D <= 
         "000" & fY_d8            when "001" | "111",
         "00" & fY_d8 & "0"     when "010" | "110",
         "0" & fYTimes3_d8             when "011" | "101",
         (26 downto 0 => '0') when others;

   w7pad <= w7_d1 & "0";
   with q7(2) select
   w6full<= w7pad - q7D when '0',
         w7pad + q7D when others;

   w6 <= w6full(24 downto 0) & "0";
   ----------------Synchro barrier, entering cycle 9----------------
   sel6 <= w6_d1(25 downto 22) & fY_d9(22);
   with sel6 select
   q6 <= 
      "001" when "00010" | "00011",
      "010" when "00100" | "00101" | "00111",
      "011" when "00110" | "01000" | "01001" | "01010" | "01011" | "01101" | "01111",
      "101" when "11000" | "10110" | "10111" | "10100" | "10101" | "10011" | "10001",
      "110" when "11010" | "11011" | "11001",
      "111" when "11100" | "11101",
      "000" when others;

   with q6 select
      q6D <= 
         "000" & fY_d9            when "001" | "111",
         "00" & fY_d9 & "0"     when "010" | "110",
         "0" & fYTimes3_d9             when "011" | "101",
         (26 downto 0 => '0') when others;

   w6pad <= w6_d1 & "0";
   with q6(2) select
   w5full<= w6pad - q6D when '0',
         w6pad + q6D when others;

   w5 <= w5full(24 downto 0) & "0";
   ----------------Synchro barrier, entering cycle 10----------------
   sel5 <= w5_d1(25 downto 22) & fY_d10(22);
   with sel5 select
   q5 <= 
      "001" when "00010" | "00011",
      "010" when "00100" | "00101" | "00111",
      "011" when "00110" | "01000" | "01001" | "01010" | "01011" | "01101" | "01111",
      "101" when "11000" | "10110" | "10111" | "10100" | "10101" | "10011" | "10001",
      "110" when "11010" | "11011" | "11001",
      "111" when "11100" | "11101",
      "000" when others;

   with q5 select
      q5D <= 
         "000" & fY_d10            when "001" | "111",
         "00" & fY_d10 & "0"     when "010" | "110",
         "0" & fYTimes3_d10             when "011" | "101",
         (26 downto 0 => '0') when others;

   w5pad <= w5_d1 & "0";
   with q5(2) select
   w4full<= w5pad - q5D when '0',
         w5pad + q5D when others;

   w4 <= w4full(24 downto 0) & "0";
   ----------------Synchro barrier, entering cycle 11----------------
   sel4 <= w4_d1(25 downto 22) & fY_d11(22);
   with sel4 select
   q4 <= 
      "001" when "00010" | "00011",
      "010" when "00100" | "00101" | "00111",
      "011" when "00110" | "01000" | "01001" | "01010" | "01011" | "01101" | "01111",
      "101" when "11000" | "10110" | "10111" | "10100" | "10101" | "10011" | "10001",
      "110" when "11010" | "11011" | "11001",
      "111" when "11100" | "11101",
      "000" when others;

   with q4 select
      q4D <= 
         "000" & fY_d11            when "001" | "111",
         "00" & fY_d11 & "0"     when "010" | "110",
         "0" & fYTimes3_d11             when "011" | "101",
         (26 downto 0 => '0') when others;

   w4pad <= w4_d1 & "0";
   with q4(2) select
   w3full<= w4pad - q4D when '0',
         w4pad + q4D when others;

   w3 <= w3full(24 downto 0) & "0";
   ----------------Synchro barrier, entering cycle 12----------------
   sel3 <= w3_d1(25 downto 22) & fY_d12(22);
   with sel3 select
   q3 <= 
      "001" when "00010" | "00011",
      "010" when "00100" | "00101" | "00111",
      "011" when "00110" | "01000" | "01001" | "01010" | "01011" | "01101" | "01111",
      "101" when "11000" | "10110" | "10111" | "10100" | "10101" | "10011" | "10001",
      "110" when "11010" | "11011" | "11001",
      "111" when "11100" | "11101",
      "000" when others;

   with q3 select
      q3D <= 
         "000" & fY_d12            when "001" | "111",
         "00" & fY_d12 & "0"     when "010" | "110",
         "0" & fYTimes3_d12             when "011" | "101",
         (26 downto 0 => '0') when others;

   w3pad <= w3_d1 & "0";
   with q3(2) select
   w2full<= w3pad - q3D when '0',
         w3pad + q3D when others;

   w2 <= w2full(24 downto 0) & "0";
   ----------------Synchro barrier, entering cycle 13----------------
   sel2 <= w2_d1(25 downto 22) & fY_d13(22);
   with sel2 select
   q2 <= 
      "001" when "00010" | "00011",
      "010" when "00100" | "00101" | "00111",
      "011" when "00110" | "01000" | "01001" | "01010" | "01011" | "01101" | "01111",
      "101" when "11000" | "10110" | "10111" | "10100" | "10101" | "10011" | "10001",
      "110" when "11010" | "11011" | "11001",
      "111" when "11100" | "11101",
      "000" when others;

   with q2 select
      q2D <= 
         "000" & fY_d13            when "001" | "111",
         "00" & fY_d13 & "0"     when "010" | "110",
         "0" & fYTimes3_d13             when "011" | "101",
         (26 downto 0 => '0') when others;

   w2pad <= w2_d1 & "0";
   with q2(2) select
   w1full<= w2pad - q2D when '0',
         w2pad + q2D when others;

   w1 <= w1full(24 downto 0) & "0";
   ----------------Synchro barrier, entering cycle 14----------------
   sel1 <= w1_d1(25 downto 22) & fY_d14(22);
   with sel1 select
   q1 <= 
      "001" when "00010" | "00011",
      "010" when "00100" | "00101" | "00111",
      "011" when "00110" | "01000" | "01001" | "01010" | "01011" | "01101" | "01111",
      "101" when "11000" | "10110" | "10111" | "10100" | "10101" | "10011" | "10001",
      "110" when "11010" | "11011" | "11001",
      "111" when "11100" | "11101",
      "000" when others;

   with q1 select
      q1D <= 
         "000" & fY_d14            when "001" | "111",
         "00" & fY_d14 & "0"     when "010" | "110",
         "0" & fYTimes3_d14             when "011" | "101",
         (26 downto 0 => '0') when others;

   w1pad <= w1_d1 & "0";
   with q1(2) select
   w0full<= w1pad - q1D when '0',
         w1pad + q1D when others;

   w0 <= w0full(24 downto 0) & "0";
   ----------------Synchro barrier, entering cycle 15----------------
   q0(2 downto 0) <= "000" when  w0_d1 = (25 downto 0 => '0')
                else w0_d1(25) & "10";
   qP13 <=      q13_d13(1 downto 0);
   qM13 <=      q13_d13(2) & "0";
   qP12 <=      q12_d12(1 downto 0);
   qM12 <=      q12_d12(2) & "0";
   qP11 <=      q11_d11(1 downto 0);
   qM11 <=      q11_d11(2) & "0";
   qP10 <=      q10_d10(1 downto 0);
   qM10 <=      q10_d10(2) & "0";
   qP9 <=      q9_d9(1 downto 0);
   qM9 <=      q9_d9(2) & "0";
   qP8 <=      q8_d8(1 downto 0);
   qM8 <=      q8_d8(2) & "0";
   qP7 <=      q7_d7(1 downto 0);
   qM7 <=      q7_d7(2) & "0";
   qP6 <=      q6_d6(1 downto 0);
   qM6 <=      q6_d6(2) & "0";
   qP5 <=      q5_d5(1 downto 0);
   qM5 <=      q5_d5(2) & "0";
   qP4 <=      q4_d4(1 downto 0);
   qM4 <=      q4_d4(2) & "0";
   qP3 <=      q3_d3(1 downto 0);
   qM3 <=      q3_d3(2) & "0";
   qP2 <=      q2_d2(1 downto 0);
   qM2 <=      q2_d2(2) & "0";
   qP1 <=      q1_d1(1 downto 0);
   qM1 <=      q1_d1(2) & "0";
   qP0 <= q0(1 downto 0);
   qM0 <= q0(2)  & "0";
   qP <= qP13 & qP12 & qP11 & qP10 & qP9 & qP8 & qP7 & qP6 & qP5 & qP4 & qP3 & qP2 & qP1 & qP0;
   qM <= qM13(0) & qM12 & qM11 & qM10 & qM9 & qM8 & qM7 & qM6 & qM5 & qM4 & qM3 & qM2 & qM1 & qM0 & "0";
   fR0 <= qP - qM;
   ----------------Synchro barrier, entering cycle 16----------------
   fR <= fR0_d1(27 downto 1);  -- odd wF
   -- normalisation
   with fR(26) select
      fRn1 <= fR(25 downto 2) & (fR(1) or fR(0)) when '1',
              fR(24 downto 0)                    when others;
   expR1 <= expR0_d16 + ("000" & (6 downto 1 => '1') & fR(26)); -- add back bias
   round <= fRn1(1) and (fRn1(2) or fRn1(0)); -- fRn1(0) is the sticky bit
   ----------------Synchro barrier, entering cycle 17----------------
   -- final rounding
   expfrac <= expR1_d1 & fRn1_d1(24 downto 2) ;
   expfracR <= expfrac + ((32 downto 1 => '0') & round_d1);
   exnR <=      "00"  when expfracR(32) = '1'   -- underflow
           else "10"  when  expfracR(32 downto 31) =  "01" -- overflow
           else "01";      -- 00, normal case
   with exnR0_d17 select
      exnRfinal <= 
         exnR   when "01", -- normal
         exnR0_d17  when others;
   R <= exnRfinal & sR_d17 & expfracR(30 downto 0);
end architecture;

--------------------------------------------------------------------------------
--                          OutputIEEE_8_23_to_8_23
-- This operator is part of the Infinite Virtual Library FloPoCoLib
-- All rights reserved 
-- Authors: F. Ferrandi  (2009-2012)
--------------------------------------------------------------------------------
-- Pipeline depth: 0 cycles

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library std;
use std.textio.all;
library work;

entity OutputIEEE_8_23_to_8_23 is
   port ( clk, rst, ce : in std_logic;
          X : in  std_logic_vector(8+23+2 downto 0);
          R : out  std_logic_vector(31 downto 0)   );
end entity;

architecture arch of OutputIEEE_8_23_to_8_23 is
signal expX :  std_logic_vector(7 downto 0);
signal fracX :  std_logic_vector(22 downto 0);
signal exnX :  std_logic_vector(1 downto 0);
signal sX : std_logic;
signal expZero : std_logic;
signal sfracX :  std_logic_vector(22 downto 0);
signal fracR :  std_logic_vector(22 downto 0);
signal expR :  std_logic_vector(7 downto 0);
begin
   process(clk)
      begin
         if clk'event and clk = '1' then
            if ce = '1' then
            end if;
         end if;
      end process;
   expX  <= X(30 downto 23);
   fracX  <= X(22 downto 0);
   exnX  <= X(33 downto 32);
   sX  <= X(31) when (exnX = "01" or exnX = "10" or exnX = "00") else '0';
   expZero  <= '1' when expX = (7 downto 0 => '0') else '0';
   -- since we have one more exponent value than IEEE (field 0...0, value emin-1),
   -- we can represent subnormal numbers whose mantissa field begins with a 1
   sfracX <= 
      (22 downto 0 => '0') when (exnX = "00") else
      '1' & fracX(22 downto 1) when (expZero = '1' and exnX = "01") else
      fracX when (exnX = "01") else 
      (22 downto 1 => '0') & exnX(0);
   fracR <= sfracX;
   expR <=  
      (7 downto 0 => '0') when (exnX = "00") else
      expX when (exnX = "01") else 
      (7 downto 0 => '1');
   R <= sX & expR & fracR; 
end architecture;

--------------------------------------------------------------------------------
--                           InputIEEE_8_23_to_8_23
-- This operator is part of the Infinite Virtual Library FloPoCoLib
-- All rights reserved 
-- Authors: Florent de Dinechin (2008)
--------------------------------------------------------------------------------
-- Pipeline depth: 0 cycles

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library std;
use std.textio.all;
library work;

entity InputIEEE_8_23_to_8_23 is
   port ( clk, rst, ce : in std_logic;
          X : in  std_logic_vector(31 downto 0);
          R : out  std_logic_vector(8+23+2 downto 0)   );
end entity;

architecture arch of InputIEEE_8_23_to_8_23 is
signal expX :  std_logic_vector(7 downto 0);
signal fracX :  std_logic_vector(22 downto 0);
signal sX : std_logic;
signal expZero : std_logic;
signal expInfty : std_logic;
signal fracZero : std_logic;
signal reprSubNormal : std_logic;
signal sfracX :  std_logic_vector(22 downto 0);
signal fracR :  std_logic_vector(22 downto 0);
signal expR :  std_logic_vector(7 downto 0);
signal infinity : std_logic;
signal zero : std_logic;
signal NaN : std_logic;
signal exnR :  std_logic_vector(1 downto 0);
begin
   process(clk)
      begin
         if clk'event and clk = '1' then
            if ce = '1' then
            end if;
         end if;
      end process;
   expX  <= X(30 downto 23);
   fracX  <= X(22 downto 0);
   sX  <= X(31);
   expZero  <= '1' when expX = (7 downto 0 => '0') else '0';
   expInfty  <= '1' when expX = (7 downto 0 => '1') else '0';
   fracZero <= '1' when fracX = (22 downto 0 => '0') else '0';
   reprSubNormal <= fracX(22);
   -- since we have one more exponent value than IEEE (field 0...0, value emin-1),
   -- we can represent subnormal numbers whose mantissa field begins with a 1
   sfracX <= fracX(21 downto 0) & '0' when (expZero='1' and reprSubNormal='1')    else fracX;
   fracR <= sfracX;
   -- copy exponent. This will be OK even for subnormals, zero and infty since in such cases the exn bits will prevail
   expR <= expX;
   infinity <= expInfty and fracZero;
   zero <= expZero and not reprSubNormal;
   NaN <= expInfty and not fracZero;
   exnR <= 
           "00" when zero='1' 
      else "10" when infinity='1' 
      else "11" when NaN='1' 
      else "01" ;  -- normal number
   R <= exnR & sX & expR & fracR; 
end architecture;

