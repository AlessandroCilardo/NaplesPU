import serial
import sys
import threading
import time
import argparse
import struct
import Queue

parser = argparse.ArgumentParser(description='Nu+ UART loader')
parser.add_argument('-k', '--kernel', help='kernel memory image path', default="kernel_mem_mango_mem.hex", required=True)
parser.add_argument('-d', '--debug', help='enable debug output', default="false")
parser.add_argument('-s', '--serial', help='serial port to use', default="", required=True)

# Arguments Parsing
args        = parser.parse_args()
kernelPath  = args.kernel
DEBUG       = args.debug == "true"
serialPort  = args.serial

# Debug Prints
print ("Nu+ UART loader called:")
print ("Kernel Path: " + kernelPath)
print ("Debug: " + str(DEBUG))
print ("Serial port: " + serialPort)
print ("\n")

def words_to_hexstr(content):
    ret = "["
    for w in content:
        ret = ret + hex(w) + ", "
    ret = ret + "]"

    return ret

def debug_print(str):
    if DEBUG:
        print(str)

class CommHandler:
    def __init__(self, device):
        self.__device = device
        self.__rx_queues = {}

        thread = threading.Thread(target=self.__receive_thread, args=())
        thread.setDaemon(True)
        thread.start()

    def __send_word(self, value):
        debug_print("Sending " + hex(value))

        tosend = bytearray([value & 0xFF,
            (value & 0xFF00) >> 8,
            (value & 0xFF0000) >> 16,
            (value & 0xFF000000) >> 24])

        debug_print("        " + hex(tosend[0]))
        debug_print("        " + hex(tosend[1]))
        debug_print("        " + hex(tosend[2]))
        debug_print("        " + hex(tosend[3]))

        self.__device.write(tosend)

    def __receive_thread(self):
        WAIT_FOR_HEADER = 0
        RECEIVE_PACKET  = 1

        rx_cnt = 0
        recv_word = 0
        word_cnt = 0
        state = WAIT_FOR_HEADER
        periph = 0

        while True:
            recv_bytes = self.__device.read(4)
            recv_word = struct.unpack("<L", recv_bytes)[0]

            if state == WAIT_FOR_HEADER:
                word_cnt = recv_word >> 16
                periph   = recv_word & 0xFFFF
                debug_print("RECV: Receiving " + str(word_cnt) + " words from peripheral " + str(periph))
                state = RECEIVE_PACKET
            else:
                debug_print("RECV: Received " + hex(recv_word) + " from peripheral " + str(periph))

                if periph in self.__rx_queues:
                    self.__rx_queues[periph].put(recv_word)
                else:
                    self.__rx_queues[periph] = Queue.Queue()
                    self.__rx_queues[periph].put(recv_word)

                word_cnt = word_cnt - 1

                if word_cnt == 0:
                    state = WAIT_FOR_HEADER

    def send_packet(self, peripheral, content):
        debug_print("PERIPH: Sending " + words_to_hexstr(content) + " to peripheral " + hex(peripheral))
        header = 0x0
        header = header | ((len(content) & 0xFFFF) << 16)
        header = header | peripheral & 0xFFFF

        self.__send_word(header)

        for i in content:
            self.__send_word(i)

    def read_packet(self, peripheral, count):
        ret = []

        while not peripheral in self.__rx_queues:
            pass

        for i in range(0, count):
            ret.append(self.__rx_queues[peripheral].get())

        return ret

def mem_write(comm, start_addr, content):
    print("MEM: Writing " + words_to_hexstr(content) + " starting from " + hex(start_addr))
    cmd = 0x80000000
    cmd = cmd | (len(content) - 1)
    comm.send_packet(0, [cmd, start_addr] + content)

def mem_read(comm, start_addr, num):
    print("MEM: Reading " + str(num) + " words starting from " + hex(start_addr))
    cmd = 0
    cmd = cmd | (num - 1)
    comm.send_packet(0, [cmd, start_addr])
    return comm.read_packet(0, num)

def npu_set_pc(comm, thread, pc):
    comm.send_packet(1, [0x0, thread, pc])

def npu_en_threads(comm, mask):
    comm.send_packet(1, [0x1, mask])

def npu_read_cr(comm, thread, regid):
    comm.send_packet(1, [0x2, (thread << 16) | regid])
    return comm.read_packet(1, 1)[0]

def npu_get_console_status(comm):
    comm.send_packet(1, [0x4])
    return comm.read_packet(1, 1)[0]

def npu_get_console_char(comm):
    comm.send_packet(1, [0x5])
    return comm.read_packet(1, 1)[0]

def npu_get_console_line(comm):
    rx_ch = 0
    ret_s = ""

    while rx_ch != ord('\n'):
        comm.send_packet(1, [0x5])
        rx_ch = comm.read_packet(1, 1)[0]
        ret_s += chr(rx_ch)

    return ret_s

def npu_send_console_char(comm, c):
    comm.send_packet(1, [0x6, ord(c)])

def npu_send_console_string(comm, s):
    for c in s:
        npu_send_console_char(comm, c)

if __name__ == '__main__':
    ser = serial.Serial(serialPort)

    if not ser.is_open:
        print('Cant open the device')
        sys.exit(1)

    comm = CommHandler(ser)

    print("Running nu+ startup self check...")
    THREAD_NUMB = npu_read_cr(comm, 0, 14)
    if THREAD_NUMB == 0:
        print("Invalid number of threads!")
        sys.exit(1)

    print("Detected " + str(THREAD_NUMB) + " threads")

    for i in range(0, THREAD_NUMB):
        read_id = npu_read_cr(comm, i, 2)
        if read_id != i:
            print("ERROR: Thread " + str(i) + " answered " + str(read_id) + "!")
            sys.exit(1)

    print("Done")
    raw_input("Press Enter to launch kernel")

    # Disable threads
    npu_en_threads(comm, 0x0)

    print("Opening kernel image")
    f = open(kernelPath)
    for line in f:
        addr = int(line[:10], 16)
        line = line[13:]

        print("Found block at " + hex(addr))

        words = []
        while line != "\n":
            word_str = line[6:8] + line[4:6] + line[2:4] + line[0:2]
            words = words + [int(word_str, 16)]
            line = line[8:]

        print("Block contents: " + words_to_hexstr(words))

        mem_write(comm, addr, words)
        time.sleep(0.1)

    # Set PC
    for i in range(0, THREAD_NUMB):
        npu_set_pc(comm, i, 0x400)
        time.sleep(0.1)

    # Enable threads
    npu_en_threads(comm, (1 << THREAD_NUMB) - 1)

    # Read back
    raw_input("Press Enter to read core info")
    print("Thread enables: " + hex(npu_read_cr(comm, 0, 6)))

    for i in range(0, THREAD_NUMB):
        print("Thread " + str(i) + " status = " + hex(npu_read_cr(comm, 0, 11)) + " PC = " + hex(npu_read_cr(comm, 0, 9)))

    argc = npu_read_cr(comm, 0, 12)
    argv = npu_read_cr(comm, 0, 13)
    print("ARGC = " + hex(argc) + " ARGV = " + hex(argv))

    debug_regs = []
    for i in range(0, 16):
        debug_regs.append(npu_read_cr(comm, 0, 20 + i))
    print("Debug registers = " + words_to_hexstr(debug_regs))

    console_status = 1
    while console_status == 1:
        console_status = npu_get_console_status(comm)
        if console_status == 1:
            time.sleep(0.1)
            rx_ch = npu_get_console_char(comm)
            print("Received console character = " + chr(rx_ch) + " (" + hex(rx_ch) + ")")

    blocks = argc / 16
    print("Reading " + str(blocks) + " blocks starting at " + hex(argv))
    for i in range(0, blocks):
        print(words_to_hexstr(mem_read(comm, argv + i*64, 16)))
