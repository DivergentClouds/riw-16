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
    // TODO: free after converting to `memory` instead
    defer allocator.free(memory_u8);

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

    try emulate(memory, &storage, allocator);
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

const locks = struct {
    io: bool = false,
    read: bool = false,
    write: bool = false,
    execute: bool = false,
    promoted: bool = false,
};

const Devices = struct {
    const kinds = enum(u16) {
        system,
        console,
        storage,
        mmu,
    };

    const ports = struct {
        const system = enum(u16) {
            syscall,
            syscall_hold_get,
            syscall_handler_set,
            syscall_handler_get,
            fault,
            fault_hold_get,
            fault_handler_set,
            fault_handler_get,
            halt,
        };

        const console = enum(u16) {
            char_out,
            char_in,
        };

        const storage = enum(u16) {
            msw_address_set,
            lsw_address_set,
            msw_address_get,
            lsw_address_get,
            storage_out,
            storage_in,
        };

        const mmu = enum(u16) {
            msw_frame_set,
            lsw_frame_set,
            msw_frame_get,
            lsw_frame_get,
            map_set,
            map_get,
            lock_io,
            unlock_io,
            lock_read,
            unlock_read,
            lock_write,
            unlock_write,
            lock_execute,
            unlock_execute,
            promote,
            demote,
        };
    };

    const state = struct {
        const System = struct {
            syscall_hold: u16 = undefined,
            syscall_handler: u16 = undefined,
            fault_handler: u16 = undefined,
            fault_hold: u16 = undefined,
            running: bool = true,
        };

        const Console = struct {
            // TODO: consider adding cursor state
        };

        const Storage = struct {
            msw_address: u16 = undefined,
            lsw_address: u16 = undefined,
        };

        const Mmu = struct {
            msw_frame: u16 = undefined,
            lsw_frame: u16 = undefined,
        };
    };

    system: state.System = state.System{},
    console: state.Console = state.Console{},
    storage: state.Storage = state.Storage{},
    mmu: state.Mmu = state.Mmu{},
};

const AccessError = error{
    IllegalWrite,
    IllegalRead,
    IllegalExecute,
    IllegalIO,
};

fn getWord(
    frames: [][256]u16,
    page_map: []u16,
    lock_map: []locks,
    is_exec: bool,
    current_address: u16,
    dest_address: u16,
) AccessError!u16 {
    const current_page = @truncate(u8, current_address >> 8);
    const dest_page = @truncate(u8, dest_address >> 8);

    if (!lock_map[current_page].promoted) {
        if (lock_map[current_page].execute)
            return error.IllegalExecute;
        if (lock_map[dest_page].read and !is_exec)
            return error.IllegalRead;
    }

    const dest_frame = page_map[dest_page];

    return frames[dest_frame][@truncate(u8, dest_address)];
}

fn setWord(
    frames: [][256]u16,
    page_map: []u16,
    lock_map: []locks,
    current_address: u16,
    dest_address: u16,
    value: u16,
) AccessError!void {
    const current_page = @truncate(u8, current_address >> 8);
    const dest_page = @truncate(u8, dest_address >> 8);

    if (!lock_map[current_page].promoted) {
        if (lock_map[dest_page].write)
            return error.IllegalWrite;
    }

    const dest_frame = page_map[dest_page];

    frames[dest_frame][@truncate(u8, dest_address)] = value;
}

fn emulate(initial_memory: []u16, storage: *std.fs.File, allocator: std.mem.Allocator) !void {
    var frames = try allocator.alloc([256]u16, 65536);

    for (0..256) |i| {
        frames[i] =
            @ptrCast(*[256][256]u16, initial_memory)[i];
    }

    var page_map: [256]u16 = [_]u16{0} ** 256;

    for (0..256) |i| {
        page_map[i] = @intCast(u16, i);
    }

    const lock_map = try allocator.alloc(locks, 256);

    var registers: [16]u16 = undefined;
    const pc: u4 = 15; // enables doing registers[pc]

    registers[pc] = 0;

    const devices = Devices{};

    while (devices.system.running) {
        const current_word: u16 = getWord(
            frames,
            &page_map,
            lock_map,
            true,
            registers[pc],
            registers[pc],
        ) catch |err| {
            switch (err) {
                error.IllegalExecute => {
                    registers[pc] = devices.system.fault_handler;
                    continue;
                },
                else => unreachable,
            }
        };

        const opcode: u4 = @truncate(u4, current_word >> 12);

        const a: u4 = @truncate(u4, current_word >> 8);

        // used in most instructions
        const b: u4 = @truncate(u4, current_word >> 4);
        const c: u4 = @truncate(u4, current_word);

        // used instead of b and c in `loct` and `uoct`
        const b_oct: u8 = @truncate(u8, current_word);

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
                registers[a] =
                    getWord(
                    frames,
                    &page_map,
                    lock_map,
                    false,
                    registers[pc],
                    @bitCast(
                        u16,
                        @bitCast(
                            i16,
                            registers[b],
                        ) +% @bitCast(
                            i16,
                            registers[c],
                        ),
                    ),
                ) catch {
                    registers[pc] = devices.system.fault_handler;
                    continue;
                };
            },
            Opcodes.store => {
                setWord(
                    frames,
                    &page_map,
                    lock_map,
                    registers[pc],
                    @bitCast(
                        u16,
                        @bitCast(
                            i16,
                            registers[b],
                        ) +% @bitCast(
                            i16,
                            registers[c],
                        ),
                    ),
                    registers[c],
                ) catch {
                    registers[pc] = devices.system.fault_handler;
                    continue;
                };
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
