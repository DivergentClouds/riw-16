const std = @import("std");
const builtin = @import("builtin");

const c = if (builtin.target.os.tag == .windows)
    @cImport({
        @cInclude("conio.h");
    })
else
    null;

const PossibleAllocators = enum {
    debug_general_purpose, // Debug Mode, GPA with extra config settings
    heap, // Windows
    c, // for if linking libc
    general_purpose, // else
};

const AllocatorType = union(PossibleAllocators) {
    debug_general_purpose: std.heap.GeneralPurposeAllocator(.{ .never_unmap = true, .retain_metadata = true }),
    heap: if (builtin.target.os.tag == .windows) std.heap.HeapAllocator else void,
    c: void,
    general_purpose: std.heap.GeneralPurposeAllocator(.{}),
};

const pc: u4 = 15; // enables doing registers[pc]

// needs to be used in signal handler, bleh
var old_termios: std.os.termios = undefined;

pub fn main() !void {
    const stderr = std.io.getStdErr();

    const allocator_kind: PossibleAllocators =
        comptime if (builtin.mode == .Debug)
        .debug_general_purpose
    else if (builtin.target.os.tag == .windows)
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

    try inputInit();
    defer inputCleanup();

    // assume posix
    if (builtin.target.os.tag != .windows) {
        var action = std.os.Sigaction{
            .handler = .{ .sigaction = posixSignalHandler },
            .mask = std.os.empty_sigset,
            .flags = (std.os.SA.SIGINFO | std.os.SA.RESTART),
        };

        try std.os.sigaction(std.os.SA.SIGINT, &action, null);
    }

    var registers: [16]u16 = [_]u16{undefined} ** 16;

    try emulate(&registers, memory, &storage, allocator);
}

fn posixSignalHandler() void {
    inputCleanup();
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
        _,
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
            _,
        };

        const console = enum(u16) {
            char_out,
            char_in,
            _,
        };

        const storage = enum(u16) {
            msw_address_set,
            lsw_address_set,
            msw_address_get,
            lsw_address_get,
            storage_out,
            storage_in,
            _,
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
            _,
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
    IllegalJump,
};

fn getWord(
    frames: [][256]u16,
    page_map: []u16,
    lock_map: []locks,
    registers: *[16]u16,
    devices: *Devices,
    is_exec: bool,
    current_address: u16,
    dest_address: u16,
) AccessError!u16 {
    const current_page = @truncate(u8, current_address >> 8);
    const dest_page = @truncate(u8, dest_address >> 8);

    if (!lock_map[current_page].promoted) {
        if (lock_map[current_page].execute) {
            fault(registers, pc, devices);
            return error.IllegalExecute;
        } else if (lock_map[dest_page].read and !is_exec) {
            fault(registers, pc, devices);
            return error.IllegalRead;
        }
    }

    const dest_frame = page_map[dest_page];

    return frames[dest_frame][@truncate(u8, dest_address)];
}

fn setWord(
    frames: [][256]u16,
    page_map: []u16,
    lock_map: []locks,
    registers: *[16]u16,
    devices: *Devices,
    current_address: u16,
    dest_address: u16,
    value: u16,
) AccessError!void {
    const current_page = @truncate(u8, current_address >> 8);
    const dest_page = @truncate(u8, dest_address >> 8);

    if (!lock_map[current_page].promoted) {
        if (lock_map[dest_page].write) {
            fault(registers, pc, devices);
            return error.IllegalWrite;
        }
    }

    const dest_frame = page_map[dest_page];

    frames[dest_frame][@truncate(u8, dest_address)] = value;
}

fn setRegister(
    registers: *[16]u16,
    id: u4,
    lock_map: []locks,
    devices: *Devices,
    current_address: u16,
    value: u16,
) AccessError!void {
    if (id == pc) {
        const current_page = @truncate(u8, current_address >> 8);
        const dest_page = @truncate(u8, value >> 8);

        if (!lock_map[current_page].promoted and
            lock_map[dest_page].promoted)
        { // attempt to jump to a promoted page from a non-promoted page
            fault(registers, pc, devices);
            return error.IllegalJump;
        }
    }
    registers[id] = value;
}

fn fault(registers: *[16]u16, id: u4, devices: *Devices) void {
    devices.system.fault_hold = registers[id];
    registers[pc] = devices.system.fault_handler;
}

fn inputInit() !void {
    if (builtin.target.os.tag == .windows) {
        return;
    }

    // Assume Posix
    old_termios = try std.os.tcgetattr(
        std.os.STDIN_FILENO,
    );
    var new_termios: std.os.termios = try std.os.tcgetattr(
        std.os.STDIN_FILENO,
    );

    // flags work for all posix systems, not just linux
    new_termios.lflag &= ~(std.os.linux.ECHO | std.os.linux.ICANON);
}
fn inputCleanup() void {
    if (builtin.target.os.tag == .windows) {
        return;
    }

    std.os.tcsetattr(
        std.os.STDIN_FILENO,
        std.os.TCSA.FLUSH,
        old_termios,
    ) catch {
        std.log.err("Could not reset terminal settings\n", .{});
    };
}

fn getCh(stdin: std.fs.File) u16 {
    var char: u16 = undefined;

    if (builtin.target.os.tag == .windows) {
        if (c._kbhit != 0) {
            char = @bitCast(u16, c._getch());

            if (char == 0 or char == 0x0e)
                _ = c._getch(); // don't deal with platform specific scancodes
        } else {
            char = 0xffff;
        }
    } else {
        var pfd = [1]std.os.pollfd{
            std.os.pollfd{
                .fd = std.os.STDIN_FILENO,
                .events = std.os.POLL.IN,
                .revents = undefined,
            },
        };

        // only error that is possible here is running out of mem
        _ = std.os.poll(&pfd, 0) catch {};

        if ((pfd.revents & std.os.POLL.IN) != 0) {
            char = try stdin.reader().readByte();
        } else {
            char = 0xffff;
        }
    }

    return char();
}

fn emulate(registers: *[16]u16, initial_memory: []u16, storage: *std.fs.File, allocator: std.mem.Allocator) !void {
    const stdin = std.io.getStdIn();
    _ = stdin;
    const stdout = std.io.getStdOut();
    const stderr = std.io.getStdErr();

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

    registers[pc] = 0;

    var devices = Devices{};

    while (devices.system.running) {
        const current_word: u16 = getWord(
            frames,
            &page_map,
            lock_map,
            registers,
            &devices,
            true,
            registers[pc],
            registers[pc],
        ) catch continue;

        const opcode: u4 = @truncate(u4, current_word >> 12);

        const arg_a: u4 = @truncate(u4, current_word >> 8);

        // used in most instructions
        const arg_b: u4 = @truncate(u4, current_word >> 4);
        const arg_c: u4 = @truncate(u4, current_word);

        // used instead of b and c in `loct` and `uoct`
        const arg_b_oct: u8 = @truncate(u8, current_word);

        switch (@intToEnum(Opcodes, opcode)) {
            Opcodes.loct => {
                const hold = (registers[arg_a] & 0xff00) | arg_b_oct;

                // check if doing disallowed jump, otherwise registers[a] = hold
                setRegister(
                    registers,
                    arg_a,
                    lock_map,
                    &devices,
                    registers[pc],
                    hold,
                ) catch continue;
            },
            Opcodes.uoct => {
                const hold = (registers[arg_a] & 0x00ff) | @as(u16, arg_b_oct) << 8;

                setRegister(
                    registers,
                    arg_a,
                    lock_map,
                    &devices,
                    registers[pc],
                    hold,
                ) catch continue;
            },
            Opcodes.addi => {
                const hold = @bitCast(
                    u16,
                    @bitCast(
                        i16,
                        registers[arg_b],
                    ) + @as(
                        i16,
                        @bitCast(
                            i4,
                            arg_c,
                        ),
                    ),
                );

                setRegister(
                    registers,
                    arg_a,
                    lock_map,
                    &devices,
                    registers[pc],
                    hold,
                ) catch continue;
            },
            Opcodes.load => {
                const hold =
                    getWord(
                    frames,
                    &page_map,
                    lock_map,
                    registers,
                    &devices,
                    false,
                    registers[pc],
                    @bitCast(
                        u16,
                        @bitCast(
                            i16,
                            registers[arg_b],
                        ) +% @bitCast(
                            i16,
                            registers[arg_c],
                        ),
                    ),
                ) catch continue;

                setRegister(
                    registers,
                    arg_a,
                    lock_map,
                    &devices,
                    registers[pc],
                    hold,
                ) catch continue;
            },
            Opcodes.store => {
                setWord(
                    frames,
                    &page_map,
                    lock_map,
                    registers,
                    &devices,
                    registers[pc],
                    @bitCast(
                        u16,
                        @bitCast(
                            i16,
                            registers[arg_b],
                        ) +% @bitCast(
                            i16,
                            registers[arg_c],
                        ),
                    ),
                    registers[arg_c],
                ) catch continue;
            },
            Opcodes.add => {
                const hold = registers[arg_b] +% registers[arg_c];

                setRegister(
                    registers,
                    arg_a,
                    lock_map,
                    &devices,
                    registers[pc],
                    hold,
                ) catch continue;
            },
            Opcodes.sub => {
                const hold = registers[arg_b] -% registers[arg_c];

                setRegister(
                    registers,
                    arg_a,
                    lock_map,
                    &devices,
                    registers[pc],
                    hold,
                ) catch continue;
            },
            Opcodes.cmp => {
                const compared = registers[arg_b] -% registers[arg_c];

                var hold = registers[arg_a] & 0b11111111_11110000;

                if (compared < 256)
                    hold |= @enumToInt(Flags.half);

                // TODO: is there a better way to do this?
                if (registers[arg_b] & (1 << 15) == registers[arg_c] & (1 << 15) // ew
                and registers[arg_b] & (1 << 15) != compared & (1 << 15))
                    hold |= @enumToInt(Flags.overflow);

                if (compared & (1 << 15) == 1 << 15)
                    hold |= @enumToInt(Flags.negative);

                if (compared == 0)
                    hold |= @enumToInt(Flags.zero);

                setRegister(
                    registers,
                    arg_a,
                    lock_map,
                    &devices,
                    registers[pc],
                    hold,
                ) catch continue;
            },
            Opcodes.branch => {
                if (@truncate(u4, registers[arg_b]) & arg_c == arg_c)
                    setRegister(
                        registers,
                        pc,
                        lock_map,
                        &devices,
                        registers[pc],
                        registers[arg_a],
                    ) catch continue;
            },
            Opcodes.shift => {
                var amount = @bitCast(i16, registers[arg_c]);
                var hold: u16 = undefined;

                if (amount < 0) {
                    amount = 0 - amount;
                    if (amount > 15) {
                        hold = 0;
                    } else {
                        hold = registers[arg_b] >> @truncate(
                            u4,
                            @bitCast(u16, amount),
                        );
                    }
                } else {
                    if (amount > 15) {
                        hold = 0;
                    } else {
                        hold = registers[arg_b] << @truncate(
                            u4,
                            @bitCast(u16, amount),
                        );
                    }
                }

                setRegister(
                    registers,
                    arg_a,
                    lock_map,
                    &devices,
                    registers[pc],
                    hold,
                ) catch continue;
            },
            Opcodes.@"and" => {
                const hold = registers[arg_b] & registers[arg_c];

                setRegister(
                    registers,
                    arg_a,
                    lock_map,
                    &devices,
                    registers[pc],
                    hold,
                ) catch continue;
            },
            Opcodes.@"or" => {
                const hold = registers[arg_b] | registers[arg_c];

                setRegister(
                    registers,
                    arg_a,
                    lock_map,
                    &devices,
                    registers[pc],
                    hold,
                ) catch continue;
            },
            Opcodes.xor => {
                const hold = registers[arg_b] ^ registers[arg_c];

                setRegister(
                    registers,
                    arg_a,
                    lock_map,
                    &devices,
                    registers[pc],
                    hold,
                ) catch continue;
            },
            Opcodes.nor => {
                const hold = ~(registers[arg_b] | registers[arg_c]);

                setRegister(
                    registers,
                    arg_a,
                    lock_map,
                    &devices,
                    registers[pc],
                    hold,
                ) catch continue;
            },
            Opcodes.swap => {
                var hold: u16 = 0;

                hold |= @as(u16, @truncate(u8, registers[arg_b])) << 8;
                hold |= registers[arg_c] >> 8;

                setRegister(
                    registers,
                    arg_a,
                    lock_map,
                    &devices,
                    registers[pc],
                    hold,
                ) catch continue;
            },
            Opcodes.io => {
                switch (@intToEnum(
                    Devices.kinds,
                    registers[arg_a],
                )) {
                    Devices.kinds.system => {
                        switch (@intToEnum(
                            Devices.ports.system,
                            registers[arg_b],
                        )) {
                            Devices.ports.system.syscall => {
                                devices.system.syscall_hold = registers[arg_c];
                                registers[pc] = devices.system.syscall_handler;
                            },
                            Devices.ports.system.syscall_hold_get => {
                                setRegister(
                                    registers,
                                    arg_c,
                                    lock_map,
                                    &devices,
                                    registers[pc],
                                    devices.system.syscall_hold,
                                ) catch continue;
                            },
                            Devices.ports.system.syscall_handler_set => {
                                devices.system.syscall_handler = registers[arg_c];
                            },
                            Devices.ports.system.syscall_handler_get => {
                                setRegister(
                                    registers,
                                    arg_c,
                                    lock_map,
                                    &devices,
                                    registers[pc],
                                    devices.system.syscall_handler,
                                ) catch continue;
                            },
                            Devices.ports.system.fault => {
                                fault(registers, arg_c, &devices);
                            },
                            Devices.ports.system.fault_hold_get => {
                                setRegister(
                                    registers,
                                    arg_c,
                                    lock_map,
                                    &devices,
                                    registers[pc],
                                    devices.system.fault_hold,
                                ) catch continue;
                            },
                            Devices.ports.system.fault_handler_set => {
                                devices.system.fault_handler = registers[arg_c];
                            },
                            Devices.ports.system.fault_handler_get => {
                                setRegister(
                                    registers,
                                    arg_c,
                                    lock_map,
                                    &devices,
                                    registers[pc],
                                    devices.system.fault_handler,
                                ) catch continue;
                            },
                            Devices.ports.system.halt => {
                                devices.system.running = false;
                            },
                            _ => {
                                fault(registers, pc, &devices);
                            },
                        }
                    },
                    Devices.kinds.console => {
                        switch (@intToEnum(
                            Devices.ports.console,
                            registers[arg_b],
                        )) {
                            Devices.ports.console.char_out => {
                                stdout.writer().writeByte(
                                    @truncate(
                                        u8,
                                        registers[arg_c],
                                    ),
                                ) catch { // handle gracefully, but if that fails, crash
                                    try stderr.writer().print(
                                        "Error on char-out at address {d}\n",
                                        .{registers[pc]},
                                    );
                                };
                            },
                            Devices.ports.console.char_in => {
                                setRegister(
                                    registers,
                                    arg_c,
                                    lock_map,
                                    &devices,
                                    registers[pc],
                                    try getCh(),
                                );
                            },
                            _ => {
                                fault(registers, pc, &devices);
                            },
                        }
                    },
                    Devices.kinds.storage => {
                        switch (@intToEnum(
                            Devices.ports.storage,
                            registers[arg_b],
                        )) {
                            Devices.ports.storage.msw_address_set => {},
                            Devices.ports.storage.lsw_address_set => {},
                            Devices.ports.storage.msw_address_get => {},
                            Devices.ports.storage.lsw_address_get => {},
                            Devices.ports.storage.storage_out => {},
                            Devices.ports.storage.storage_in => {},
                            _ => {
                                fault(registers, pc, &devices);
                            },
                        }
                    },
                    Devices.kinds.mmu => {
                        switch (@intToEnum(
                            Devices.ports.mmu,
                            registers[arg_b],
                        )) {
                            Devices.ports.mmu.msw_frame_set => {},
                            Devices.ports.mmu.lsw_frame_set => {},
                            Devices.ports.mmu.msw_frame_get => {},
                            Devices.ports.mmu.lsw_frame_get => {},
                            Devices.ports.mmu.map_set => {},
                            Devices.ports.mmu.map_get => {},
                            Devices.ports.mmu.lock_io => {},
                            Devices.ports.mmu.unlock_io => {},
                            Devices.ports.mmu.lock_read => {},
                            Devices.ports.mmu.unlock_read => {},
                            Devices.ports.mmu.lock_write => {},
                            Devices.ports.mmu.unlock_write => {},
                            Devices.ports.mmu.lock_execute => {},
                            Devices.ports.mmu.unlock_execute => {},
                            Devices.ports.mmu.promote => {},
                            Devices.ports.mmu.demote => {},
                            _ => {
                                fault(registers, pc, &devices);
                            },
                        }
                    },
                    _ => {
                        fault(registers, pc, &devices);
                    },
                }
            },
        }
    }

    _ = storage;
}
