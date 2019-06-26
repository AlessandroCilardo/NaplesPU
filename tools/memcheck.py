import argparse
import sys,re,struct,ctypes

parser = argparse.ArgumentParser(description='NPU memory checker.')
parser.add_argument('-f', '--filein', help='memory file path', default = "display_memory.txt")
parser.add_argument('-a', '--addr', help='initial hex address', default = 0)
parser.add_argument('-b', '--bnum', help='number of blocks to parse', default = 1)
parser.add_argument('-i', '--isfl', help='output in floating point format', default = 0)
parser.add_argument('-s', '--swap', help='swap memory output', default = 0)
parser.add_argument('-o', '--fileout', help='out file path', default = "result.txt")

# Arguments Parsing
args        = parser.parse_args()
fileInPath  = args.filein
fileOutPath = args.fileout
baseAddress = int(args.addr, 16) 
blockNumb   = int(args.bnum, 10)  
isFloat     = int(args.isfl)
isSwap      = int(args.swap)

# Debug Prints
print ("\n\nNPU Memory Checker called:")
print ("File Path: %s" % fileInPath)
print ("Address: %d" % baseAddress)
print ("Block numb: %d" % blockNumb)
print ("Is FLoat: %d\n\n" % isFloat)
print ("Output Path: %s" % fileOutPath)

# Open the input file
Fin  = open(fileInPath,"r")
Fout = open(fileOutPath, "w")

# Initializate lists and calculate both starting and ending rows
ListFloat = []
ListMem   = []
ListInt   = []
fromLine  = baseAddress / 64 + 1
toLine    = fromLine + blockNumb - 1 

# Parse the memory file
for i in range(0, toLine):
    line = Fin.readline()
    tmp = line.rstrip('\n')
    if i >= (fromLine - 1):
        tmp = re.split('\t', tmp)
        parsed_line = tmp[1]
        parsed_line = parsed_line[1:]
        mem_list = []
        float_list = []
        int_list = []

        for j in range(0, len(parsed_line), 8):
            z = (parsed_line[j: j + 8])
            mem_list = mem_list + [z]
        ListMem.append(mem_list)

        for k in range(0, 16):
            if isSwap == 1:
	        float_val = mem_list[k][6:8] + mem_list[k][4:6] + mem_list[k][2:4] + mem_list[k][0:2]
            else:
	        float_val = mem_list[k] 
            float_val = struct.unpack('!f', float_val.decode('hex'))[0]
            float_list = float_list + [float_val] 
            
            if isSwap == 1:
	        int_val = int(mem_list[k][6:8] + mem_list[k][4:6] + mem_list[k][2:4] + mem_list[k][0:2], 16)
	    else:
                int_val = int(mem_list[k], 16)
            if int_val > 0x7FFFFFFF:
	        int_val -= 0x100000000
            int_list = int_list + [int_val] 
        ListFloat.append(float_list)
        ListInt.append(int_list)
        
        
print 'Memory Image: '
for j in range(0, len(ListMem)):
    print (' '.join(ListMem[j]))

print '\n\nTraslation: '
printcounter = 1
for j in range(0, len(ListInt)):
    line_to_file = []
    s = []
    if isFloat == 1:
	for v in reversed(ListFloat[j]):
		s = "%8.4f " % v
        	line_to_file.append(s)
		if printcounter % 16 == 0:
			print s
			line_to_file.append("\n")
		else:
			print s, 	
		printcounter+=1
    else:
	for v in reversed(ListInt[j]):
		s = "%8d " % v
                line_to_file.append(s)
		if printcounter % 16 == 0:
			print s
			line_to_file.append("\n")
		else:
			print s,
		printcounter+=1
    Fout.write(' '.join(line_to_file)) 

Fin.close()
Fout.close()
