const std = @import("std");
const Allocator = std.mem.Allocator;
const instruction = @import("instruction.zig");
const Instruction = instruction.Instruction;
const Operand = instruction.Operand;
const printer = @import("printer.zig");

fn getEAClocks(operand: Operand) usize {
    switch (operand) {
        .direct_address => {
            return 6;
        },
        .mem_calc_no_disp => {
            return 5;
        },
        .mem_calc_with_disp => |calc| {
            switch (calc.disp) {
                .byte => |val| {
                    if (val == 0) {
                        return 5;
                    } else {
                        return 9;
                    }
                },
                .word => |val| {
                    if (val == 0) {
                        return 5;
                    } else {
                        return 9;
                    }
                }
            }
        },
        else => {}
    }

    return 0;
}

fn getMovClocks(inst: Instruction) usize {
    switch(inst.operand1) {
        .register => {
            switch(inst.operand2.?) {
                .register => {
                    return 2;
                },
                .immediate => {
                    return 4;
                },
                .mem_calc_with_disp, .mem_calc_no_disp, .direct_address => {
                    return 8 + getEAClocks(inst.operand2.?);
                },
                else => {
                    return 0;
                }
            }
        },
        .mem_calc_with_disp, .mem_calc_no_disp => {
            switch (inst.operand2.?) {
                .register => {
                    return 9 + getEAClocks(inst.operand1);
                },
                else => {
                }
            }
        },
        else => {
        }
    }
    return 0;
}

fn getAddClocks(inst: Instruction) usize {
    switch(inst.operand1) {
        .register => {
            switch(inst.operand2.?) {
                .register => {
                    return 3;
                },
                .immediate => {
                    return 4;
                },
                .mem_calc_with_disp, .mem_calc_no_disp, .direct_address => {
                    return 9 + getEAClocks(inst.operand2.?);
                },
                else => {
                }
            }
        },
        .mem_calc_with_disp, .mem_calc_no_disp => {
            switch (inst.operand2.?) {
                .register => {
                    return 16 + getEAClocks(inst.operand1);
                },
                else => {
                }
            }
        },
        else => {
        }
    }
    return 0;
}

fn getClocks(inst: Instruction) usize {
    var result: usize = 0;

    switch (inst.opcode) {
        .mov => {
            result = getMovClocks(inst);
        },
        .add => {
            result = getAddClocks(inst);
        },
        else => {}
    }

    return result;
}

pub fn printClocks(allocator: Allocator, insts: []Instruction) !void {
    const stdout = std.io.getStdOut().writer();
    var total_clocks: usize = 0;
    try stdout.print("\n====== Clocks estimation ======\n", .{});
    for (insts) |inst| {
        const clocks = getClocks(inst);
        total_clocks += clocks;
        try printer.printInstruction(allocator, inst);
        try stdout.print("; Clocks: {d}\n", .{clocks});
    }
    try stdout.print("Total clocks: {d}\n", .{total_clocks});
    try stdout.print("======================================\n", .{});
}
