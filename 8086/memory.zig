// Even though 8086 had 1MB of memory 
// to address it I will need to implement the segment registers.
// I don't want to do that yet so I'm sticking to 64 KB, which
// is addressable by 16 bit registers.
var memory: [64000]u8 = undefined;

pub fn store(address: u16, value: u8) void {
    memory[address] = value;
}

pub fn load(address: u16) u8 {
    return memory[address];
}
