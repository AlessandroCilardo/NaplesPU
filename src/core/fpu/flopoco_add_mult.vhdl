--------------------------------------------------------------------------------
--                    RightShifter_24_by_max_26_F270_uid4
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

entity RightShifter_24_by_max_26_F270_uid4 is
   port ( clk, rst, ce : in std_logic;
          X : in  std_logic_vector(23 downto 0);
          S : in  std_logic_vector(4 downto 0);
          R : out  std_logic_vector(49 downto 0)   );
end entity;

architecture arch of RightShifter_24_by_max_26_F270_uid4 is
signal level0 :  std_logic_vector(23 downto 0);
signal ps, ps_d1 :  std_logic_vector(4 downto 0);
signal level1 :  std_logic_vector(24 downto 0);
signal level2 :  std_logic_vector(26 downto 0);
signal level3 :  std_logic_vector(30 downto 0);
signal level4, level4_d1 :  std_logic_vector(38 downto 0);
signal level5 :  std_logic_vector(54 downto 0);
begin
   process(clk)
      begin
         if clk'event and clk = '1' then
            if ce = '1' then
               ps_d1 <=  ps;
               level4_d1 <=  level4;
            end if;
         end if;
      end process;
   level0<= X;
   ps<= S;
   level1<=  (0 downto 0 => '0') & level0 when ps(0) = '1' else    level0 & (0 downto 0 => '0');
   level2<=  (1 downto 0 => '0') & level1 when ps(1) = '1' else    level1 & (1 downto 0 => '0');
   level3<=  (3 downto 0 => '0') & level2 when ps(2) = '1' else    level2 & (3 downto 0 => '0');
   level4<=  (7 downto 0 => '0') & level3 when ps(3) = '1' else    level3 & (7 downto 0 => '0');
   ----------------Synchro barrier, entering cycle 1----------------
   level5<=  (15 downto 0 => '0') & level4_d1 when ps_d1(4) = '1' else    level4_d1 & (15 downto 0 => '0');
   R <= level5(54 downto 5);
end architecture;

--------------------------------------------------------------------------------
--                           IntAdder_27_f270_uid8
--                     (IntAdderClassical_27_F270_uid10)
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

entity IntAdder_27_f270_uid8 is
   port ( clk, rst, ce : in std_logic;
          X : in  std_logic_vector(26 downto 0);
          Y : in  std_logic_vector(26 downto 0);
          Cin : in  std_logic;
          R : out  std_logic_vector(26 downto 0)   );
end entity;

architecture arch of IntAdder_27_f270_uid8 is
begin
   process(clk)
      begin
         if clk'event and clk = '1' then
            if ce = '1' then
            end if;
         end if;
      end process;
   --Classical
    R <= X + Y + Cin;
end architecture;

--------------------------------------------------------------------------------
--                 LZCShifter_28_to_28_counting_32_F270_uid16
-- This operator is part of the Infinite Virtual Library FloPoCoLib
-- All rights reserved 
-- Authors: Florent de Dinechin, Bogdan Pasca (2007)
--------------------------------------------------------------------------------
-- Pipeline depth: 2 cycles

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library std;
use std.textio.all;
library work;

entity LZCShifter_28_to_28_counting_32_F270_uid16 is
   port ( clk, rst, ce : in std_logic;
          I : in  std_logic_vector(27 downto 0);
          Count : out  std_logic_vector(4 downto 0);
          O : out  std_logic_vector(27 downto 0)   );
end entity;

architecture arch of LZCShifter_28_to_28_counting_32_F270_uid16 is
signal level5 :  std_logic_vector(27 downto 0);
signal count4, count4_d1, count4_d2 :  std_logic;
signal level4 :  std_logic_vector(27 downto 0);
signal count3, count3_d1, count3_d2 :  std_logic;
signal level3, level3_d1 :  std_logic_vector(27 downto 0);
signal count2, count2_d1 :  std_logic;
signal level2 :  std_logic_vector(27 downto 0);
signal count1, count1_d1 :  std_logic;
signal level1, level1_d1 :  std_logic_vector(27 downto 0);
signal count0, count0_d1 :  std_logic;
signal level0 :  std_logic_vector(27 downto 0);
signal sCount :  std_logic_vector(4 downto 0);
begin
   process(clk)
      begin
         if clk'event and clk = '1' then
            if ce = '1' then
               count4_d1 <=  count4;
               count4_d2 <=  count4_d1;
               count3_d1 <=  count3;
               count3_d2 <=  count3_d1;
               level3_d1 <=  level3;
               count2_d1 <=  count2;
               count1_d1 <=  count1;
               level1_d1 <=  level1;
               count0_d1 <=  count0;
            end if;
         end if;
      end process;
   level5 <= I ;
   count4<= '1' when level5(27 downto 12) = (27 downto 12=>'0') else '0';
   level4<= level5(27 downto 0) when count4='0' else level5(11 downto 0) & (15 downto 0 => '0');

   count3<= '1' when level4(27 downto 20) = (27 downto 20=>'0') else '0';
   level3<= level4(27 downto 0) when count3='0' else level4(19 downto 0) & (7 downto 0 => '0');

   ----------------Synchro barrier, entering cycle 1----------------
   count2<= '1' when level3_d1(27 downto 24) = (27 downto 24=>'0') else '0';
   level2<= level3_d1(27 downto 0) when count2='0' else level3_d1(23 downto 0) & (3 downto 0 => '0');

   count1<= '1' when level2(27 downto 26) = (27 downto 26=>'0') else '0';
   level1<= level2(27 downto 0) when count1='0' else level2(25 downto 0) & (1 downto 0 => '0');

   count0<= '1' when level1(27 downto 27) = (27 downto 27=>'0') else '0';
   ----------------Synchro barrier, entering cycle 2----------------
   level0<= level1_d1(27 downto 0) when count0_d1='0' else level1_d1(26 downto 0) & (0 downto 0 => '0');

   O <= level0;
   sCount <= count4_d2 & count3_d2 & count2_d1 & count1_d1 & count0_d1;
   Count <= sCount;
end architecture;

--------------------------------------------------------------------------------
--                           IntAdder_34_f270_uid20
--                     (IntAdderClassical_34_F270_uid22)
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

entity IntAdder_34_f270_uid20 is
   port ( clk, rst, ce : in std_logic;
          X : in  std_logic_vector(33 downto 0);
          Y : in  std_logic_vector(33 downto 0);
          Cin : in  std_logic;
          R : out  std_logic_vector(33 downto 0)   );
end entity;

architecture arch of IntAdder_34_f270_uid20 is
begin
   process(clk)
      begin
         if clk'event and clk = '1' then
            if ce = '1' then
            end if;
         end if;
      end process;
   --Classical
    R <= X + Y + Cin;
end architecture;

--------------------------------------------------------------------------------
--                            FPAdd_8_23_F270_uid2
-- This operator is part of the Infinite Virtual Library FloPoCoLib
-- All rights reserved 
-- Authors: Bogdan Pasca, Florent de Dinechin (2010)
--------------------------------------------------------------------------------
-- Pipeline depth: 5 cycles

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library std;
use std.textio.all;
library work;

entity FPAdd_8_23_F270_uid2 is
   port ( clk, rst, ce : in std_logic;
          X : in  std_logic_vector(8+23+2 downto 0);
          Y : in  std_logic_vector(8+23+2 downto 0);
          R : out  std_logic_vector(8+23+2 downto 0)   );
end entity;

architecture arch of FPAdd_8_23_F270_uid2 is
   component RightShifter_24_by_max_26_F270_uid4 is
      port ( clk, rst, ce : in std_logic;
             X : in  std_logic_vector(23 downto 0);
             S : in  std_logic_vector(4 downto 0);
             R : out  std_logic_vector(49 downto 0)   );
   end component;

   component IntAdder_27_f270_uid8 is
      port ( clk, rst, ce : in std_logic;
             X : in  std_logic_vector(26 downto 0);
             Y : in  std_logic_vector(26 downto 0);
             Cin : in  std_logic;
             R : out  std_logic_vector(26 downto 0)   );
   end component;

   component LZCShifter_28_to_28_counting_32_F270_uid16 is
      port ( clk, rst, ce : in std_logic;
             I : in  std_logic_vector(27 downto 0);
             Count : out  std_logic_vector(4 downto 0);
             O : out  std_logic_vector(27 downto 0)   );
   end component;

   component IntAdder_34_f270_uid20 is
      port ( clk, rst, ce : in std_logic;
             X : in  std_logic_vector(33 downto 0);
             Y : in  std_logic_vector(33 downto 0);
             Cin : in  std_logic;
             R : out  std_logic_vector(33 downto 0)   );
   end component;

signal excExpFracX :  std_logic_vector(32 downto 0);
signal excExpFracY :  std_logic_vector(32 downto 0);
signal eXmeY :  std_logic_vector(8 downto 0);
signal eYmeX :  std_logic_vector(8 downto 0);
signal swap :  std_logic;
signal newX, newX_d1, newX_d2 :  std_logic_vector(33 downto 0);
signal newY :  std_logic_vector(33 downto 0);
signal expX, expX_d1, expX_d2 :  std_logic_vector(7 downto 0);
signal excX :  std_logic_vector(1 downto 0);
signal excY :  std_logic_vector(1 downto 0);
signal signX, signX_d1 :  std_logic;
signal signY :  std_logic;
signal EffSub, EffSub_d1, EffSub_d2, EffSub_d3, EffSub_d4, EffSub_d5 :  std_logic;
signal sXsYExnXY, sXsYExnXY_d1 :  std_logic_vector(5 downto 0);
signal sdExnXY :  std_logic_vector(3 downto 0);
signal fracY :  std_logic_vector(23 downto 0);
signal excRt, excRt_d1, excRt_d2, excRt_d3, excRt_d4, excRt_d5 :  std_logic_vector(1 downto 0);
signal signR, signR_d1, signR_d2, signR_d3, signR_d4 :  std_logic;
signal expDiff :  std_logic_vector(8 downto 0);
signal shiftedOut :  std_logic;
signal shiftVal :  std_logic_vector(4 downto 0);
signal shiftedFracY, shiftedFracY_d1 :  std_logic_vector(49 downto 0);
signal sticky :  std_logic;
signal fracYfar :  std_logic_vector(26 downto 0);
signal EffSubVector :  std_logic_vector(26 downto 0);
signal fracYfarXorOp :  std_logic_vector(26 downto 0);
signal fracXfar :  std_logic_vector(26 downto 0);
signal cInAddFar :  std_logic;
signal fracAddResult :  std_logic_vector(26 downto 0);
signal fracGRS :  std_logic_vector(27 downto 0);
signal extendedExpInc, extendedExpInc_d1, extendedExpInc_d2 :  std_logic_vector(9 downto 0);
signal nZerosNew :  std_logic_vector(4 downto 0);
signal shiftedFrac :  std_logic_vector(27 downto 0);
signal updatedExp :  std_logic_vector(9 downto 0);
signal eqdiffsign, eqdiffsign_d1 :  std_logic;
signal expFrac :  std_logic_vector(33 downto 0);
signal stk :  std_logic;
signal rnd :  std_logic;
signal grd :  std_logic;
signal lsb :  std_logic;
signal addToRoundBit :  std_logic;
signal RoundedExpFrac :  std_logic_vector(33 downto 0);
signal upExc :  std_logic_vector(1 downto 0);
signal fracR, fracR_d1 :  std_logic_vector(22 downto 0);
signal expR, expR_d1 :  std_logic_vector(7 downto 0);
signal exExpExc :  std_logic_vector(3 downto 0);
signal excRt2, excRt2_d1 :  std_logic_vector(1 downto 0);
signal excR :  std_logic_vector(1 downto 0);
signal signR2 :  std_logic;
signal computedR :  std_logic_vector(33 downto 0);
begin
   process(clk)
      begin
         if clk'event and clk = '1' then
            if ce = '1' then
               newX_d1 <=  newX;
               newX_d2 <=  newX_d1;
               expX_d1 <=  expX;
               expX_d2 <=  expX_d1;
               signX_d1 <=  signX;
               EffSub_d1 <=  EffSub;
               EffSub_d2 <=  EffSub_d1;
               EffSub_d3 <=  EffSub_d2;
               EffSub_d4 <=  EffSub_d3;
               EffSub_d5 <=  EffSub_d4;
               sXsYExnXY_d1 <=  sXsYExnXY;
               excRt_d1 <=  excRt;
               excRt_d2 <=  excRt_d1;
               excRt_d3 <=  excRt_d2;
               excRt_d4 <=  excRt_d3;
               excRt_d5 <=  excRt_d4;
               signR_d1 <=  signR;
               signR_d2 <=  signR_d1;
               signR_d3 <=  signR_d2;
               signR_d4 <=  signR_d3;
               shiftedFracY_d1 <=  shiftedFracY;
               extendedExpInc_d1 <=  extendedExpInc;
               extendedExpInc_d2 <=  extendedExpInc_d1;
               eqdiffsign_d1 <=  eqdiffsign;
               fracR_d1 <=  fracR;
               expR_d1 <=  expR;
               excRt2_d1 <=  excRt2;
            end if;
         end if;
      end process;
-- Exponent difference and swap  --
   excExpFracX <= X(33 downto 32) & X(30 downto 0);
   excExpFracY <= Y(33 downto 32) & Y(30 downto 0);
   eXmeY <= ("0" & X(30 downto 23)) - ("0" & Y(30 downto 23));
   eYmeX <= ("0" & Y(30 downto 23)) - ("0" & X(30 downto 23));
   swap <= '0' when excExpFracX >= excExpFracY else '1';
   newX <= X when swap = '0' else Y;
   newY <= Y when swap = '0' else X;
   expX<= newX(30 downto 23);
   excX<= newX(33 downto 32);
   excY<= newY(33 downto 32);
   signX<= newX(31);
   signY<= newY(31);
   EffSub <= signX xor signY;
   sXsYExnXY <= signX & signY & excX & excY;
   sdExnXY <= excX & excY;
   fracY <= "000000000000000000000000" when excY="00" else ('1' & newY(22 downto 0));
   with sXsYExnXY select 
   excRt <= "00" when "000000"|"010000"|"100000"|"110000",
      "01" when "000101"|"010101"|"100101"|"110101"|"000100"|"010100"|"100100"|"110100"|"000001"|"010001"|"100001"|"110001",
      "10" when "111010"|"001010"|"001000"|"011000"|"101000"|"111000"|"000010"|"010010"|"100010"|"110010"|"001001"|"011001"|"101001"|"111001"|"000110"|"010110"|"100110"|"110110", 
      "11" when others;
   ----------------Synchro barrier, entering cycle 1----------------
   signR<= '0' when (sXsYExnXY_d1="100000" or sXsYExnXY_d1="010000") else signX_d1;
   ---------------- cycle 0----------------
   expDiff <= eXmeY when swap = '0' else eYmeX;
   shiftedOut <= '1' when (expDiff > 25) else '0';
   shiftVal <= expDiff(4 downto 0) when shiftedOut='0' else CONV_STD_LOGIC_VECTOR(26,5) ;
   RightShifterComponent: RightShifter_24_by_max_26_F270_uid4  -- pipelineDepth=1 maxInDelay=0
      port map ( clk  => clk,
                 rst  => rst,
                 ce => ce,
                 R => shiftedFracY,
                 S => shiftVal,
                 X => fracY);
   ----------------Synchro barrier, entering cycle 1----------------
   ----------------Synchro barrier, entering cycle 2----------------
   sticky <= '0' when (shiftedFracY_d1(23 downto 0)=CONV_STD_LOGIC_VECTOR(0,24)) else '1';
   ---------------- cycle 1----------------
   ----------------Synchro barrier, entering cycle 2----------------
   fracYfar <= "0" & shiftedFracY_d1(49 downto 24);
   EffSubVector <= (26 downto 0 => EffSub_d2);
   fracYfarXorOp <= fracYfar xor EffSubVector;
   fracXfar <= "01" & (newX_d2(22 downto 0)) & "00";
   cInAddFar <= EffSub_d2 and not sticky;
   fracAdder: IntAdder_27_f270_uid8  -- pipelineDepth=0 maxInDelay=0
      port map ( clk  => clk,
                 rst  => rst,
                 ce => ce,
                 Cin => cInAddFar,
                 R => fracAddResult,
                 X => fracXfar,
                 Y => fracYfarXorOp);
   fracGRS<= fracAddResult & sticky; 
   extendedExpInc<= ("00" & expX_d2) + '1';
   LZC_component: LZCShifter_28_to_28_counting_32_F270_uid16  -- pipelineDepth=2 maxInDelay=0
      port map ( clk  => clk,
                 rst  => rst,
                 ce => ce,
                 Count => nZerosNew,
                 I => fracGRS,
                 O => shiftedFrac);
   ----------------Synchro barrier, entering cycle 4----------------
   updatedExp <= extendedExpInc_d2 - ("00000" & nZerosNew);
   eqdiffsign <= '1' when nZerosNew="11111" else '0';
   expFrac<= updatedExp & shiftedFrac(26 downto 3);
   ---------------- cycle 4----------------
   stk<= shiftedFrac(1) or shiftedFrac(0);
   rnd<= shiftedFrac(2);
   grd<= shiftedFrac(3);
   lsb<= shiftedFrac(4);
   addToRoundBit<= '0' when (lsb='0' and grd='1' and rnd='0' and stk='0')  else '1';
   roundingAdder: IntAdder_34_f270_uid20  -- pipelineDepth=0 maxInDelay=0
      port map ( clk  => clk,
                 rst  => rst,
                 ce => ce,
                 Cin => addToRoundBit,
                 R => RoundedExpFrac,
                 X => expFrac,
                 Y => "0000000000000000000000000000000000");
   ---------------- cycle 4----------------
   upExc <= RoundedExpFrac(33 downto 32);
   fracR <= RoundedExpFrac(23 downto 1);
   expR <= RoundedExpFrac(31 downto 24);
   exExpExc <= upExc & excRt_d4;
   with (exExpExc) select 
   excRt2<= "00" when "0000"|"0100"|"1000"|"1100"|"1001"|"1101",
      "01" when "0001",
      "10" when "0010"|"0110"|"1010"|"1110"|"0101",
      "11" when others;
   ----------------Synchro barrier, entering cycle 5----------------
   excR <= "00" when (eqdiffsign_d1='1' and EffSub_d5='1' and not(excRt_d5="11")) else excRt2_d1;
   signR2 <= '0' when (eqdiffsign_d1='1' and EffSub_d5='1') else signR_d4;
   computedR <= excR & signR2 & expR_d1 & fracR_d1;
   R <= computedR;
end architecture;

--------------------------------------------------------------------------------
--                           IntAdder_42_f270_uid41
--                     (IntAdderClassical_42_F270_uid43)
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

entity IntAdder_42_f270_uid41 is
   port ( clk, rst, ce : in std_logic;
          X : in  std_logic_vector(41 downto 0);
          Y : in  std_logic_vector(41 downto 0);
          Cin : in  std_logic;
          R : out  std_logic_vector(41 downto 0)   );
end entity;

architecture arch of IntAdder_42_f270_uid41 is
begin
   process(clk)
      begin
         if clk'event and clk = '1' then
            if ce = '1' then
            end if;
         end if;
      end process;
   --Classical
    R <= X + Y + Cin;
end architecture;

--------------------------------------------------------------------------------
--            IntMultiplier_UsingDSP_24_24_48_unsigned_F270_uid30
-- This operator is part of the Infinite Virtual Library FloPoCoLib
-- All rights reserved 
-- Authors: Florent de Dinechin, Kinga Illyes, Bogdan Popa, Bogdan Pasca, 2012
--------------------------------------------------------------------------------
-- Pipeline depth: 1 cycles

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library std;
use std.textio.all;
library work;

entity IntMultiplier_UsingDSP_24_24_48_unsigned_F270_uid30 is
   port ( clk, rst, ce : in std_logic;
          X : in  std_logic_vector(23 downto 0);
          Y : in  std_logic_vector(23 downto 0);
          R : out  std_logic_vector(47 downto 0)   );
end entity;

architecture arch of IntMultiplier_UsingDSP_24_24_48_unsigned_F270_uid30 is
   component IntAdder_42_f270_uid41 is
      port ( clk, rst, ce : in std_logic;
             X : in  std_logic_vector(41 downto 0);
             Y : in  std_logic_vector(41 downto 0);
             Cin : in  std_logic;
             R : out  std_logic_vector(41 downto 0)   );
   end component;

signal XX_m31 :  std_logic_vector(23 downto 0);
signal YY_m31 :  std_logic_vector(23 downto 0);
signal DSP_bh32_ch0_0 :  std_logic_vector(40 downto 0);
signal heap_bh32_w47_0, heap_bh32_w47_0_d1 :  std_logic;
signal heap_bh32_w46_0, heap_bh32_w46_0_d1 :  std_logic;
signal heap_bh32_w45_0, heap_bh32_w45_0_d1 :  std_logic;
signal heap_bh32_w44_0, heap_bh32_w44_0_d1 :  std_logic;
signal heap_bh32_w43_0, heap_bh32_w43_0_d1 :  std_logic;
signal heap_bh32_w42_0, heap_bh32_w42_0_d1 :  std_logic;
signal heap_bh32_w41_0, heap_bh32_w41_0_d1 :  std_logic;
signal heap_bh32_w40_0, heap_bh32_w40_0_d1 :  std_logic;
signal heap_bh32_w39_0, heap_bh32_w39_0_d1 :  std_logic;
signal heap_bh32_w38_0, heap_bh32_w38_0_d1 :  std_logic;
signal heap_bh32_w37_0, heap_bh32_w37_0_d1 :  std_logic;
signal heap_bh32_w36_0, heap_bh32_w36_0_d1 :  std_logic;
signal heap_bh32_w35_0, heap_bh32_w35_0_d1 :  std_logic;
signal heap_bh32_w34_0, heap_bh32_w34_0_d1 :  std_logic;
signal heap_bh32_w33_0, heap_bh32_w33_0_d1 :  std_logic;
signal heap_bh32_w32_0, heap_bh32_w32_0_d1 :  std_logic;
signal heap_bh32_w31_0, heap_bh32_w31_0_d1 :  std_logic;
signal heap_bh32_w30_0, heap_bh32_w30_0_d1 :  std_logic;
signal heap_bh32_w29_0, heap_bh32_w29_0_d1 :  std_logic;
signal heap_bh32_w28_0, heap_bh32_w28_0_d1 :  std_logic;
signal heap_bh32_w27_0, heap_bh32_w27_0_d1 :  std_logic;
signal heap_bh32_w26_0, heap_bh32_w26_0_d1 :  std_logic;
signal heap_bh32_w25_0, heap_bh32_w25_0_d1 :  std_logic;
signal heap_bh32_w24_0, heap_bh32_w24_0_d1 :  std_logic;
signal heap_bh32_w23_0, heap_bh32_w23_0_d1 :  std_logic;
signal heap_bh32_w22_0, heap_bh32_w22_0_d1 :  std_logic;
signal heap_bh32_w21_0, heap_bh32_w21_0_d1 :  std_logic;
signal heap_bh32_w20_0, heap_bh32_w20_0_d1 :  std_logic;
signal heap_bh32_w19_0, heap_bh32_w19_0_d1 :  std_logic;
signal heap_bh32_w18_0, heap_bh32_w18_0_d1 :  std_logic;
signal heap_bh32_w17_0, heap_bh32_w17_0_d1 :  std_logic;
signal heap_bh32_w16_0, heap_bh32_w16_0_d1 :  std_logic;
signal heap_bh32_w15_0, heap_bh32_w15_0_d1 :  std_logic;
signal heap_bh32_w14_0, heap_bh32_w14_0_d1 :  std_logic;
signal heap_bh32_w13_0, heap_bh32_w13_0_d1 :  std_logic;
signal heap_bh32_w12_0, heap_bh32_w12_0_d1 :  std_logic;
signal heap_bh32_w11_0, heap_bh32_w11_0_d1 :  std_logic;
signal heap_bh32_w10_0, heap_bh32_w10_0_d1 :  std_logic;
signal heap_bh32_w9_0, heap_bh32_w9_0_d1 :  std_logic;
signal heap_bh32_w8_0, heap_bh32_w8_0_d1 :  std_logic;
signal heap_bh32_w7_0, heap_bh32_w7_0_d1 :  std_logic;
signal DSP_bh32_ch1_0 :  std_logic_vector(40 downto 0);
signal heap_bh32_w30_1, heap_bh32_w30_1_d1 :  std_logic;
signal heap_bh32_w29_1, heap_bh32_w29_1_d1 :  std_logic;
signal heap_bh32_w28_1, heap_bh32_w28_1_d1 :  std_logic;
signal heap_bh32_w27_1, heap_bh32_w27_1_d1 :  std_logic;
signal heap_bh32_w26_1, heap_bh32_w26_1_d1 :  std_logic;
signal heap_bh32_w25_1, heap_bh32_w25_1_d1 :  std_logic;
signal heap_bh32_w24_1, heap_bh32_w24_1_d1 :  std_logic;
signal heap_bh32_w23_1, heap_bh32_w23_1_d1 :  std_logic;
signal heap_bh32_w22_1, heap_bh32_w22_1_d1 :  std_logic;
signal heap_bh32_w21_1, heap_bh32_w21_1_d1 :  std_logic;
signal heap_bh32_w20_1, heap_bh32_w20_1_d1 :  std_logic;
signal heap_bh32_w19_1, heap_bh32_w19_1_d1 :  std_logic;
signal heap_bh32_w18_1, heap_bh32_w18_1_d1 :  std_logic;
signal heap_bh32_w17_1, heap_bh32_w17_1_d1 :  std_logic;
signal heap_bh32_w16_1, heap_bh32_w16_1_d1 :  std_logic;
signal heap_bh32_w15_1, heap_bh32_w15_1_d1 :  std_logic;
signal heap_bh32_w14_1, heap_bh32_w14_1_d1 :  std_logic;
signal heap_bh32_w13_1, heap_bh32_w13_1_d1 :  std_logic;
signal heap_bh32_w12_1, heap_bh32_w12_1_d1 :  std_logic;
signal heap_bh32_w11_1, heap_bh32_w11_1_d1 :  std_logic;
signal heap_bh32_w10_1, heap_bh32_w10_1_d1 :  std_logic;
signal heap_bh32_w9_1, heap_bh32_w9_1_d1 :  std_logic;
signal heap_bh32_w8_1, heap_bh32_w8_1_d1 :  std_logic;
signal heap_bh32_w7_1, heap_bh32_w7_1_d1 :  std_logic;
signal heap_bh32_w6_0 :  std_logic;
signal heap_bh32_w5_0 :  std_logic;
signal heap_bh32_w4_0 :  std_logic;
signal heap_bh32_w3_0 :  std_logic;
signal heap_bh32_w2_0 :  std_logic;
signal heap_bh32_w1_0 :  std_logic;
signal heap_bh32_w0_0 :  std_logic;
signal finalAdderIn0_bh32 :  std_logic_vector(41 downto 0);
signal finalAdderIn1_bh32 :  std_logic_vector(41 downto 0);
signal finalAdderCin_bh32 :  std_logic;
signal finalAdderOut_bh32 :  std_logic_vector(41 downto 0);
signal tempR_bh32_0, tempR_bh32_0_d1 :  std_logic_vector(6 downto 0);
signal CompressionResult32 :  std_logic_vector(48 downto 0);
begin
   process(clk)
      begin
         if clk'event and clk = '1' then
            if ce = '1' then
               heap_bh32_w47_0_d1 <=  heap_bh32_w47_0;
               heap_bh32_w46_0_d1 <=  heap_bh32_w46_0;
               heap_bh32_w45_0_d1 <=  heap_bh32_w45_0;
               heap_bh32_w44_0_d1 <=  heap_bh32_w44_0;
               heap_bh32_w43_0_d1 <=  heap_bh32_w43_0;
               heap_bh32_w42_0_d1 <=  heap_bh32_w42_0;
               heap_bh32_w41_0_d1 <=  heap_bh32_w41_0;
               heap_bh32_w40_0_d1 <=  heap_bh32_w40_0;
               heap_bh32_w39_0_d1 <=  heap_bh32_w39_0;
               heap_bh32_w38_0_d1 <=  heap_bh32_w38_0;
               heap_bh32_w37_0_d1 <=  heap_bh32_w37_0;
               heap_bh32_w36_0_d1 <=  heap_bh32_w36_0;
               heap_bh32_w35_0_d1 <=  heap_bh32_w35_0;
               heap_bh32_w34_0_d1 <=  heap_bh32_w34_0;
               heap_bh32_w33_0_d1 <=  heap_bh32_w33_0;
               heap_bh32_w32_0_d1 <=  heap_bh32_w32_0;
               heap_bh32_w31_0_d1 <=  heap_bh32_w31_0;
               heap_bh32_w30_0_d1 <=  heap_bh32_w30_0;
               heap_bh32_w29_0_d1 <=  heap_bh32_w29_0;
               heap_bh32_w28_0_d1 <=  heap_bh32_w28_0;
               heap_bh32_w27_0_d1 <=  heap_bh32_w27_0;
               heap_bh32_w26_0_d1 <=  heap_bh32_w26_0;
               heap_bh32_w25_0_d1 <=  heap_bh32_w25_0;
               heap_bh32_w24_0_d1 <=  heap_bh32_w24_0;
               heap_bh32_w23_0_d1 <=  heap_bh32_w23_0;
               heap_bh32_w22_0_d1 <=  heap_bh32_w22_0;
               heap_bh32_w21_0_d1 <=  heap_bh32_w21_0;
               heap_bh32_w20_0_d1 <=  heap_bh32_w20_0;
               heap_bh32_w19_0_d1 <=  heap_bh32_w19_0;
               heap_bh32_w18_0_d1 <=  heap_bh32_w18_0;
               heap_bh32_w17_0_d1 <=  heap_bh32_w17_0;
               heap_bh32_w16_0_d1 <=  heap_bh32_w16_0;
               heap_bh32_w15_0_d1 <=  heap_bh32_w15_0;
               heap_bh32_w14_0_d1 <=  heap_bh32_w14_0;
               heap_bh32_w13_0_d1 <=  heap_bh32_w13_0;
               heap_bh32_w12_0_d1 <=  heap_bh32_w12_0;
               heap_bh32_w11_0_d1 <=  heap_bh32_w11_0;
               heap_bh32_w10_0_d1 <=  heap_bh32_w10_0;
               heap_bh32_w9_0_d1 <=  heap_bh32_w9_0;
               heap_bh32_w8_0_d1 <=  heap_bh32_w8_0;
               heap_bh32_w7_0_d1 <=  heap_bh32_w7_0;
               heap_bh32_w30_1_d1 <=  heap_bh32_w30_1;
               heap_bh32_w29_1_d1 <=  heap_bh32_w29_1;
               heap_bh32_w28_1_d1 <=  heap_bh32_w28_1;
               heap_bh32_w27_1_d1 <=  heap_bh32_w27_1;
               heap_bh32_w26_1_d1 <=  heap_bh32_w26_1;
               heap_bh32_w25_1_d1 <=  heap_bh32_w25_1;
               heap_bh32_w24_1_d1 <=  heap_bh32_w24_1;
               heap_bh32_w23_1_d1 <=  heap_bh32_w23_1;
               heap_bh32_w22_1_d1 <=  heap_bh32_w22_1;
               heap_bh32_w21_1_d1 <=  heap_bh32_w21_1;
               heap_bh32_w20_1_d1 <=  heap_bh32_w20_1;
               heap_bh32_w19_1_d1 <=  heap_bh32_w19_1;
               heap_bh32_w18_1_d1 <=  heap_bh32_w18_1;
               heap_bh32_w17_1_d1 <=  heap_bh32_w17_1;
               heap_bh32_w16_1_d1 <=  heap_bh32_w16_1;
               heap_bh32_w15_1_d1 <=  heap_bh32_w15_1;
               heap_bh32_w14_1_d1 <=  heap_bh32_w14_1;
               heap_bh32_w13_1_d1 <=  heap_bh32_w13_1;
               heap_bh32_w12_1_d1 <=  heap_bh32_w12_1;
               heap_bh32_w11_1_d1 <=  heap_bh32_w11_1;
               heap_bh32_w10_1_d1 <=  heap_bh32_w10_1;
               heap_bh32_w9_1_d1 <=  heap_bh32_w9_1;
               heap_bh32_w8_1_d1 <=  heap_bh32_w8_1;
               heap_bh32_w7_1_d1 <=  heap_bh32_w7_1;
               tempR_bh32_0_d1 <=  tempR_bh32_0;
            end if;
         end if;
      end process;
   XX_m31 <= X ;
   YY_m31 <= Y ;
   
   -- Beginning of code generated by BitHeap::generateCompressorVHDL
   -- code generated by BitHeap::generateSupertileVHDL()
   ----------------Synchro barrier, entering cycle 0----------------
   DSP_bh32_ch0_0 <= std_logic_vector(unsigned("" & XX_m31(23 downto 0) & "") * unsigned("" & YY_m31(23 downto 7) & ""));
   heap_bh32_w47_0 <= DSP_bh32_ch0_0(40); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w46_0 <= DSP_bh32_ch0_0(39); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w45_0 <= DSP_bh32_ch0_0(38); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w44_0 <= DSP_bh32_ch0_0(37); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w43_0 <= DSP_bh32_ch0_0(36); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w42_0 <= DSP_bh32_ch0_0(35); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w41_0 <= DSP_bh32_ch0_0(34); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w40_0 <= DSP_bh32_ch0_0(33); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w39_0 <= DSP_bh32_ch0_0(32); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w38_0 <= DSP_bh32_ch0_0(31); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w37_0 <= DSP_bh32_ch0_0(30); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w36_0 <= DSP_bh32_ch0_0(29); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w35_0 <= DSP_bh32_ch0_0(28); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w34_0 <= DSP_bh32_ch0_0(27); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w33_0 <= DSP_bh32_ch0_0(26); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w32_0 <= DSP_bh32_ch0_0(25); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w31_0 <= DSP_bh32_ch0_0(24); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w30_0 <= DSP_bh32_ch0_0(23); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w29_0 <= DSP_bh32_ch0_0(22); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w28_0 <= DSP_bh32_ch0_0(21); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w27_0 <= DSP_bh32_ch0_0(20); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w26_0 <= DSP_bh32_ch0_0(19); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w25_0 <= DSP_bh32_ch0_0(18); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w24_0 <= DSP_bh32_ch0_0(17); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w23_0 <= DSP_bh32_ch0_0(16); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w22_0 <= DSP_bh32_ch0_0(15); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w21_0 <= DSP_bh32_ch0_0(14); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w20_0 <= DSP_bh32_ch0_0(13); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w19_0 <= DSP_bh32_ch0_0(12); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w18_0 <= DSP_bh32_ch0_0(11); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w17_0 <= DSP_bh32_ch0_0(10); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w16_0 <= DSP_bh32_ch0_0(9); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w15_0 <= DSP_bh32_ch0_0(8); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w14_0 <= DSP_bh32_ch0_0(7); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w13_0 <= DSP_bh32_ch0_0(6); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w12_0 <= DSP_bh32_ch0_0(5); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w11_0 <= DSP_bh32_ch0_0(4); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w10_0 <= DSP_bh32_ch0_0(3); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w9_0 <= DSP_bh32_ch0_0(2); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w8_0 <= DSP_bh32_ch0_0(1); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w7_0 <= DSP_bh32_ch0_0(0); -- cycle= 0 cp= 2.387e-09
   ----------------Synchro barrier, entering cycle 0----------------
   DSP_bh32_ch1_0 <= std_logic_vector(unsigned("" & XX_m31(23 downto 0) & "") * unsigned("" & YY_m31(6 downto 0) & "0000000000"));
   heap_bh32_w30_1 <= DSP_bh32_ch1_0(40); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w29_1 <= DSP_bh32_ch1_0(39); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w28_1 <= DSP_bh32_ch1_0(38); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w27_1 <= DSP_bh32_ch1_0(37); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w26_1 <= DSP_bh32_ch1_0(36); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w25_1 <= DSP_bh32_ch1_0(35); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w24_1 <= DSP_bh32_ch1_0(34); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w23_1 <= DSP_bh32_ch1_0(33); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w22_1 <= DSP_bh32_ch1_0(32); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w21_1 <= DSP_bh32_ch1_0(31); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w20_1 <= DSP_bh32_ch1_0(30); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w19_1 <= DSP_bh32_ch1_0(29); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w18_1 <= DSP_bh32_ch1_0(28); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w17_1 <= DSP_bh32_ch1_0(27); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w16_1 <= DSP_bh32_ch1_0(26); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w15_1 <= DSP_bh32_ch1_0(25); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w14_1 <= DSP_bh32_ch1_0(24); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w13_1 <= DSP_bh32_ch1_0(23); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w12_1 <= DSP_bh32_ch1_0(22); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w11_1 <= DSP_bh32_ch1_0(21); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w10_1 <= DSP_bh32_ch1_0(20); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w9_1 <= DSP_bh32_ch1_0(19); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w8_1 <= DSP_bh32_ch1_0(18); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w7_1 <= DSP_bh32_ch1_0(17); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w6_0 <= DSP_bh32_ch1_0(16); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w5_0 <= DSP_bh32_ch1_0(15); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w4_0 <= DSP_bh32_ch1_0(14); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w3_0 <= DSP_bh32_ch1_0(13); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w2_0 <= DSP_bh32_ch1_0(12); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w1_0 <= DSP_bh32_ch1_0(11); -- cycle= 0 cp= 2.387e-09
   heap_bh32_w0_0 <= DSP_bh32_ch1_0(10); -- cycle= 0 cp= 2.387e-09
   ----------------Synchro barrier, entering cycle 0----------------

   -- Adding the constant bits
      -- All the constant bits are zero, nothing to add

   ----------------Synchro barrier, entering cycle 0----------------
   ----------------Synchro barrier, entering cycle 0----------------
   ----------------Synchro barrier, entering cycle 1----------------
   finalAdderIn0_bh32 <= "0" & heap_bh32_w47_0_d1 & heap_bh32_w46_0_d1 & heap_bh32_w45_0_d1 & heap_bh32_w44_0_d1 & heap_bh32_w43_0_d1 & heap_bh32_w42_0_d1 & heap_bh32_w41_0_d1 & heap_bh32_w40_0_d1 & heap_bh32_w39_0_d1 & heap_bh32_w38_0_d1 & heap_bh32_w37_0_d1 & heap_bh32_w36_0_d1 & heap_bh32_w35_0_d1 & heap_bh32_w34_0_d1 & heap_bh32_w33_0_d1 & heap_bh32_w32_0_d1 & heap_bh32_w31_0_d1 & heap_bh32_w30_1_d1 & heap_bh32_w29_1_d1 & heap_bh32_w28_1_d1 & heap_bh32_w27_1_d1 & heap_bh32_w26_1_d1 & heap_bh32_w25_1_d1 & heap_bh32_w24_1_d1 & heap_bh32_w23_1_d1 & heap_bh32_w22_1_d1 & heap_bh32_w21_1_d1 & heap_bh32_w20_1_d1 & heap_bh32_w19_1_d1 & heap_bh32_w18_1_d1 & heap_bh32_w17_1_d1 & heap_bh32_w16_1_d1 & heap_bh32_w15_1_d1 & heap_bh32_w14_1_d1 & heap_bh32_w13_1_d1 & heap_bh32_w12_1_d1 & heap_bh32_w11_1_d1 & heap_bh32_w10_1_d1 & heap_bh32_w9_1_d1 & heap_bh32_w8_1_d1 & heap_bh32_w7_1_d1;
   finalAdderIn1_bh32 <= "0" & '0' & '0' & '0' & '0' & '0' & '0' & '0' & '0' & '0' & '0' & '0' & '0' & '0' & '0' & '0' & '0' & '0' & heap_bh32_w30_0_d1 & heap_bh32_w29_0_d1 & heap_bh32_w28_0_d1 & heap_bh32_w27_0_d1 & heap_bh32_w26_0_d1 & heap_bh32_w25_0_d1 & heap_bh32_w24_0_d1 & heap_bh32_w23_0_d1 & heap_bh32_w22_0_d1 & heap_bh32_w21_0_d1 & heap_bh32_w20_0_d1 & heap_bh32_w19_0_d1 & heap_bh32_w18_0_d1 & heap_bh32_w17_0_d1 & heap_bh32_w16_0_d1 & heap_bh32_w15_0_d1 & heap_bh32_w14_0_d1 & heap_bh32_w13_0_d1 & heap_bh32_w12_0_d1 & heap_bh32_w11_0_d1 & heap_bh32_w10_0_d1 & heap_bh32_w9_0_d1 & heap_bh32_w8_0_d1 & heap_bh32_w7_0_d1;
   finalAdderCin_bh32 <= '0';
   Adder_final32_0: IntAdder_42_f270_uid41  -- pipelineDepth=0 maxInDelay=0
      port map ( clk  => clk,
                 rst  => rst,
                 ce => ce,
                 Cin => finalAdderCin_bh32,
                 R => finalAdderOut_bh32   ,
                 X => finalAdderIn0_bh32,
                 Y => finalAdderIn1_bh32);
   ----------------Synchro barrier, entering cycle 0----------------
   tempR_bh32_0 <= heap_bh32_w6_0 & heap_bh32_w5_0 & heap_bh32_w4_0 & heap_bh32_w3_0 & heap_bh32_w2_0 & heap_bh32_w1_0 & heap_bh32_w0_0; -- already compressed
   -- concatenate all the compressed chunks
   ----------------Synchro barrier, entering cycle 1----------------
   CompressionResult32 <= finalAdderOut_bh32 & tempR_bh32_0_d1;
   -- End of code generated by BitHeap::generateCompressorVHDL
   R <= CompressionResult32(47 downto 0);
end architecture;

--------------------------------------------------------------------------------
--                           IntAdder_33_f270_uid51
--                     (IntAdderClassical_33_F270_uid53)
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

entity IntAdder_33_f270_uid51 is
   port ( clk, rst, ce : in std_logic;
          X : in  std_logic_vector(32 downto 0);
          Y : in  std_logic_vector(32 downto 0);
          Cin : in  std_logic;
          R : out  std_logic_vector(32 downto 0)   );
end entity;

architecture arch of IntAdder_33_f270_uid51 is
signal X_d1 :  std_logic_vector(32 downto 0);
signal Y_d1 :  std_logic_vector(32 downto 0);
signal Cin_d1 :  std_logic;
begin
   process(clk)
      begin
         if clk'event and clk = '1' then
            if ce = '1' then
               X_d1 <=  X;
               Y_d1 <=  Y;
               Cin_d1 <=  Cin;
            end if;
         end if;
      end process;
   --Classical
   ----------------Synchro barrier, entering cycle 1----------------
    R <= X_d1 + Y_d1 + Cin_d1;
end architecture;

--------------------------------------------------------------------------------
--                      FPMult_8_23_8_23_8_23_F270_uid28
-- This operator is part of the Infinite Virtual Library FloPoCoLib
-- All rights reserved 
-- Authors: Bogdan Pasca, Florent de Dinechin 2008-2011
--------------------------------------------------------------------------------
-- Pipeline depth: 2 cycles

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library std;
use std.textio.all;
library work;

entity FPMult_8_23_8_23_8_23_F270_uid28 is
   port ( clk, rst, ce : in std_logic;
          X : in  std_logic_vector(8+23+2 downto 0);
          Y : in  std_logic_vector(8+23+2 downto 0);
          R : out  std_logic_vector(8+23+2 downto 0)   );
end entity;

architecture arch of FPMult_8_23_8_23_8_23_F270_uid28 is
   component IntMultiplier_UsingDSP_24_24_48_unsigned_F270_uid30 is
      port ( clk, rst, ce : in std_logic;
             X : in  std_logic_vector(23 downto 0);
             Y : in  std_logic_vector(23 downto 0);
             R : out  std_logic_vector(47 downto 0)   );
   end component;

   component IntAdder_33_f270_uid51 is
      port ( clk, rst, ce : in std_logic;
             X : in  std_logic_vector(32 downto 0);
             Y : in  std_logic_vector(32 downto 0);
             Cin : in  std_logic;
             R : out  std_logic_vector(32 downto 0)   );
   end component;

signal sign, sign_d1, sign_d2 :  std_logic;
signal expX :  std_logic_vector(7 downto 0);
signal expY :  std_logic_vector(7 downto 0);
signal expSumPreSub :  std_logic_vector(9 downto 0);
signal bias :  std_logic_vector(9 downto 0);
signal expSum, expSum_d1 :  std_logic_vector(9 downto 0);
signal sigX :  std_logic_vector(23 downto 0);
signal sigY :  std_logic_vector(23 downto 0);
signal sigProd :  std_logic_vector(47 downto 0);
signal excSel :  std_logic_vector(3 downto 0);
signal exc, exc_d1, exc_d2 :  std_logic_vector(1 downto 0);
signal norm :  std_logic;
signal expPostNorm :  std_logic_vector(9 downto 0);
signal sigProdExt :  std_logic_vector(47 downto 0);
signal expSig :  std_logic_vector(32 downto 0);
signal sticky :  std_logic;
signal guard :  std_logic;
signal round :  std_logic;
signal expSigPostRound :  std_logic_vector(32 downto 0);
signal excPostNorm :  std_logic_vector(1 downto 0);
signal finalExc :  std_logic_vector(1 downto 0);
begin
   process(clk)
      begin
         if clk'event and clk = '1' then
            if ce = '1' then
               sign_d1 <=  sign;
               sign_d2 <=  sign_d1;
               expSum_d1 <=  expSum;
               exc_d1 <=  exc;
               exc_d2 <=  exc_d1;
            end if;
         end if;
      end process;
   sign <= X(31) xor Y(31);
   expX <= X(30 downto 23);
   expY <= Y(30 downto 23);
   expSumPreSub <= ("00" & expX) + ("00" & expY);
   bias <= CONV_STD_LOGIC_VECTOR(127,10);
   expSum <= expSumPreSub - bias;
   ----------------Synchro barrier, entering cycle 0----------------
   sigX <= "1" & X(22 downto 0);
   sigY <= "1" & Y(22 downto 0);
   SignificandMultiplication: IntMultiplier_UsingDSP_24_24_48_unsigned_F270_uid30  -- pipelineDepth=1 maxInDelay=0
      port map ( clk  => clk,
                 rst  => rst,
                 ce => ce,
                 R => sigProd,
                 X => sigX,
                 Y => sigY);
   ----------------Synchro barrier, entering cycle 1----------------
   ----------------Synchro barrier, entering cycle 0----------------
   excSel <= X(33 downto 32) & Y(33 downto 32);
   with excSel select 
   exc <= "00" when  "0000" | "0001" | "0100", 
          "01" when "0101",
          "10" when "0110" | "1001" | "1010" ,
          "11" when others;
   ----------------Synchro barrier, entering cycle 1----------------
   norm <= sigProd(47);
   -- exponent update
   expPostNorm <= expSum_d1 + ("000000000" & norm);
   ----------------Synchro barrier, entering cycle 1----------------
   -- significand normalization shift
   sigProdExt <= sigProd(46 downto 0) & "0" when norm='1' else
                         sigProd(45 downto 0) & "00";
   expSig <= expPostNorm & sigProdExt(47 downto 25);
   sticky <= sigProdExt(24);
   guard <= '0' when sigProdExt(23 downto 0)="000000000000000000000000" else '1';
   round <= sticky and ( (guard and not(sigProdExt(25))) or (sigProdExt(25) ))  ;
   RoundingAdder: IntAdder_33_f270_uid51  -- pipelineDepth=1 maxInDelay=2.80116e-09
      port map ( clk  => clk,
                 rst  => rst,
                 ce => ce,
                 Cin => round,
                 R => expSigPostRound   ,
                 X => expSig,
                 Y => "000000000000000000000000000000000");
   ----------------Synchro barrier, entering cycle 2----------------
   with expSigPostRound(32 downto 31) select
   excPostNorm <=  "01"  when  "00",
                               "10"             when "01", 
                               "00"             when "11"|"10",
                               "11"             when others;
   with exc_d2 select 
   finalExc <= exc_d2 when  "11"|"10"|"00",
                       excPostNorm when others; 
   R <= finalExc & sign_d2 & expSigPostRound(30 downto 0);
end architecture;

