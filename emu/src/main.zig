const std = @import("std");
const builtin = @import("builtin");

const PossibleAllocators = enum {
    debug_general_purpose, // Debug Mode, GPA with extra config settings
    heap, // Windows
    c, // for if linking libc
    general_purpose, // else
};

const AllocatorType = union(PossibleAllocators) {
    debug_general_purpose: std.heap.GeneralPurposeAllocator(.{ .never_unmap = true, .retain_metadata = true }),
    heap: if (builtin.os.tag == .windows) std.heap.HeapAllocator else void,
    c: void,
    general_purpose: std.heap.GeneralPurposeAllocator(.{}),
};

pub fn main() !void {
    const stderr = std.io.getStdErr();

    const allocator_kind: PossibleAllocators =
        comptime if (builtin.mode == .Debug)
        .debug_general_purpose
    else if (builtin.os.tag == .windows)
        .heap
    else if (builtin.link_libc)
        .c
    else
        .general_purpose;

    var allocator_type = switch (allocator_kind) {
        .debug_general_purpose => std.heap.GeneralPurposeAllocator(.{ .never_unmap = true, .retain_metadata = true }){},
        .heap => std.heap.HeapAllocator.init(),
        .c => {},
        .general_purpose => std.heap.GeneralPurposeAllocator(.{}){},
    };

    defer {
        if (allocator_kind != .c) {
            _ = allocator_type.deinit();
        }
    }

    const allocator = if (allocator_kind == .c)
        std.heap.c_allocator
    else
        allocator_type.allocator();

    // defer if (builtin.mode == .Debug) std.debug.assert(gpa.deinit() == .ok);

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 3) {
        stderr.writer().print(
            "Usage:\n{s} <memory file> <storage file>\n",
            .{args[0]},
        ) catch {};
        return error.BadArgs;
    }

    const memory_size = @as(usize, 1) << 16; // 1 << 16 words

    var memory_file = try std.fs.cwd().openFile(args[1], .{});
    defer memory_file.close();

    const memory_file_metadata = try memory_file.metadata();

    if (memory_file_metadata.size() > memory_size * 2) { // in bytes
        stderr.writeAll("Memory file must not be > 128 KiB\n") catch {};
        return error.MemoryFileTooLarge;
    }

    var memory_u8 = try allocator.alloc(u8, memory_size * 2); // in bytes
    defer allocator.free(memory_u8); // TODO: free after converting to `memory`

    _ = try std.fs.cwd().readFile(
        args[1],
        memory_u8,
    );

    var memory = try allocator.alloc(u16, memory_size);
    defer allocator.free(memory);

    for (memory, 0..) |*item, index| {
        item.* = std.mem.readIntBig(
            u16,
            @ptrCast(
                *[2]u8,
                memory_u8[index * 2 .. index * 2 + 1],
            ),
        );
    }

    var storage = std.fs.cwd().openFile(
        args[2],
        .{
            .mode = .read_write,
            .lock = .Shared,
        },
    ) catch |err| blk: {
        switch (err) {
            std.fs.File.OpenError.FileNotFound => {
                break :blk try std.fs.cwd().createFile(
                    args[2],
                    .{
                        .lock = .Shared,
                    },
                );
            },
            else => return err,
        }
    };
    defer storage.close();

    try emulate(memory, &storage);
}

const Flags = enum(u4) {
    half = 0b1000,
    overflow = 0b0100,
    negative = 0b0010,
    zero = 0b0001,
};

const Opcodes = enum(u4) {
    /// loct $A, B
    loct,
    /// uoct $A, B
    uoct,
    /// addi $A, $B, C
    addi,
    /// load $A, $B, $C
    load,
    /// store $A, $B, $C
    store,
    /// add $A, $B, $C
    add,
    /// sub $A, $B, $C
    sub,
    /// cmp $A, $B, $C
    cmp,
    /// branch $A, $B, C
    branch,
    /// shift $A, $B, $C
    shift,
    /// and $A, $B, $C
    @"and",
    /// or $A, $B, $C
    @"or",
    /// xor $A, $B, $C
    xor,
    /// nor $A, $B, $C
    nor,
    /// swap $A, $B, $C
    swap,
    /// io $A, $B, $C
    io,
};

fn emulate(memory: []u16, storage: *std.fs.File) !void {
    var registers: [16]u16 = undefined;
    const pc: u4 = 15; // enables doing registers[pc]

    registers[pc] = 0;

    var running = true;
    while (running) {
        const opcode: u4 = @truncate(u4, memory[registers[pc]] >> 12);

        const a: u4 = @truncate(u4, memory[registers[pc]] >> 8);

        // used in most instructions
        const b: u4 = @truncate(u4, memory[registers[pc]] >> 4);
        const c: u4 = @truncate(u4, memory[registers[pc]]);

        // used instead of b and c in `loct` and `uoct`
        const b_oct: u8 = @truncate(u8, memory[registers[pc]]);

        switch (@intToEnum(Opcodes, opcode)) {
            Opcodes.loct => {
                registers[a] &= 0xff00;
                registers[a] |= b_oct;
            },
            Opcodes.uoct => {
                registers[a] &= 0x00ff;
                registers[a] |= @as(u16, b_oct) << 8;
            },
            Opcodes.addi => {
                registers[a] = @bitCast(
                    u16,
                    @bitCast(
                        i16,
                        registers[b],
                    ) + @as(
                        i16,
                        @bitCast(
                            i4,
                            c,
                        ),
                    ),
                );
            },
            Opcodes.load => {
                registers[a] = memory[
                    @bitCast(
                        u16,
                        @bitCast(
                            i16,
                            registers[b],
                        ) +% @bitCast(
                            i16,
                            registers[c],
                        ),
                    )
                ];
            },
            Opcodes.store => {
                memory[
                    @bitCast(
                        u16,
                        @bitCast(
                            i16,
                            registers[b],
                        ) +% @bitCast(
                            i16,
                            registers[c],
                        ),
                    )
                ] = registers[c];
            },
            Opcodes.add => {
                registers[a] = registers[b] +% registers[c];
            },
            Opcodes.sub => {
                registers[a] = registers[b] -% registers[c];
            },
            Opcodes.cmp => {
                const compared = registers[b] -% registers[c];

                registers[a] &= 0b11111111_11110000;

                if (compared < 256)
                    registers[a] |= @enumToInt(Flags.half);

                // TODO: is there a better way to do this?
                if (registers[b] & (1 << 15) == registers[c] & (1 << 15) // ew
                and registers[b] & (1 << 15) != compared & (1 << 15))
                    registers[a] |= @enumToInt(Flags.overflow);

                if (compared & (1 << 15) == 1 << 15)
                    registers[a] |= @enumToInt(Flags.negative);

                if (compared == 0)
                    registers[a] |= @enumToInt(Flags.zero);
            },
            Opcodes.branch => {
                if (@truncate(u4, registers[b]) & c == c)
                    registers[pc] = registers[a];
            },
            Opcodes.shift => {
                var amount = @bitCast(i16, registers[c]);

                if (amount < 0) {
                    amount = 0 - amount;
                    if (amount > 15) {
                        registers[a] = 0;
                    } else {
                        registers[a] = registers[b] >> @truncate(
                            u4,
                            @bitCast(u16, amount),
                        );
                    }
                } else {
                    if (amount > 15) {
                        registers[a] = 0;
                    } else {
                        registers[a] = registers[b] << @truncate(
                            u4,
                            @bitCast(u16, amount),
                        );
                    }
                }
            },
            Opcodes.@"and" => {
                registers[a] = registers[b] & registers[c];
            },
            Opcodes.@"or" => {
                registers[a] = registers[b] | registers[c];
            },
            Opcodes.xor => {
                registers[a] = registers[b] ^ registers[c];
            },
            Opcodes.nor => {
                registers[a] = ~(registers[b] | registers[c]);
            },
            Opcodes.swap => {
                var result: u16 = 0;

                result |= @as(u16, @truncate(u8, registers[b])) << 8;
                result |= registers[c] >> 8;

                registers[a] = result;
            },
            Opcodes.io => {},
        }
    }

    _ = storage;
}
