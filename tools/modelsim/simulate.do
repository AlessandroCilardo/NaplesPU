do {utils.do}
do {wave.do}

view wave
view structure
view signals

set StdArithNoWarnings 1
set NumericStdNoWarnings 1
set Resolution ns

log -r /*

onfinish final

run -all
