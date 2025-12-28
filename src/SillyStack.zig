const std = @import("std");
const expect = std.testing.expect;
const mem = std.mem;
const Allocator = mem.Allocator;

pub const Prog = struct {
	const Self = @This();
	const DEFAULT_STACK_SIZE : u32 = 256;

	_allocator: Allocator,
	prog: []u8,
	stack: std.ArrayList(i32),

	pub const Samples = struct {
		pub const prog_hello_world:[] const u8 = "avqmimcfdddfviiffvddfavdegmfavdmcwfwdddfvddfwdfwdddf";
		pub const prog_cat:[] const u8 = "jf";
		pub const prog_factorial:[] const u8 =
			\\h # Set X
			\\q # Duplicate x (z)
			\\d # Decrement z (y)
			\\t # Begin loop
			\\    m # Multiply y by x
			\\    l # Swap result and y
			\\    d # Decrement y
			\\u # End loop
			\\b # Pop remaining 0
			\\x # Print (x!)
		;
	};

	pub fn init(allocator: Allocator) !Self {
		return Self {
			._allocator = allocator,
			.prog = &.{},
			.stack = try std.ArrayList(i32).initCapacity(allocator, DEFAULT_STACK_SIZE),
		};
	}

	pub fn deinit(self: *Self) void {
		self.resetProg();
		self.stack.deinit(self._allocator);
	}

	pub fn resetProg(self: *Self) void {
		self._allocator.free(self.prog);
		self.prog = &.{};
	}

	pub fn clearStack(self: *Self) void {
		self.stack.clearRetainingCapacity();
	}

	pub fn getTopStackValOrNull(self: *Self) ?i32 {
		return self.stack.getLastOrNull();
	}

	pub const ProcessError = error {
		SyntaxError,
		AllocationFailed
	};

	pub const RuntimeError = error {
		BadStackAccess,
		CmdNotImplemented,
	};

	fn processProgram(prog: [] const u8, self: ?*Self) ProcessError!usize {
		const len = prog.len;
		var pos: usize = 0;
		var prog_len: usize = 0;

		const compiling: bool = (self != null);

		if (compiling) {
			if (self.?.prog.len > 0) { self.?.resetProg(); }
			const sz = try analyze(prog);
			std.debug.print("\n Prog size: {d}\n", .{sz});
			self.?.prog = self.?._allocator.alloc(u8, sz) catch {
				return ProcessError.AllocationFailed;
			};
		}

		while (pos < len) {
			const ch = prog[pos];
			switch (ch) {
				'\n', ' ', '\t','\r' => pos += 1,

				'#' => {
					pos += 1;
					while ((pos < len) and (prog[pos] != '\n')) {
						pos += 1;
					}
				},

				'A'...'Z', 'a'...'z' => {
					if (compiling) {
						std.debug.print("\t{d} : {c}\n", .{prog_len, ch});
						self.?.prog[prog_len] = std.ascii.toLower(ch);
					}
					prog_len += 1;
					pos += 1;
				},

				else => {
					std.debug.print("\nBad symbol |{c}| at position {d}\n", .{ch, pos});
					return ProcessError.SyntaxError;
				},
			}
		}

		return prog_len;
	}

	fn convertToU8(value: i32) u8 {
		return std.math.cast(u8, value) 
			orelse {
				std.debug.print("Conversion failed\n", .{});
				return 0; // Default value
			};
	}


	pub fn run(self: *Self, io: std.Io) !void {
		if (self.prog.len == 0) { return; }
		var prog_pos: u32 = 0;
		var skip_next: bool = false;
		self.clearStack();
		var stdin_buffer: [512]u8 = undefined;
		var stdin_reader = std.fs.File.stdin().reader(io, &stdin_buffer);
		const stdin_ifc = &stdin_reader.interface;

		while (prog_pos < self.prog.len) {
			if (skip_next) {
				skip_next = false;
				prog_pos += 1;
				continue;
			}
			const cmd = self.prog[prog_pos];
			switch (cmd) {
				'a' => try self.stack.append(self._allocator, 0),
				'b' => _ = self.stack.pop(),
				'c' => {
					if (self.stack.items.len < 2) { return RuntimeError.BadStackAccess; }

					const idx0 = self.stack.items.len - 1;
					const idx1 = self.stack.items.len - 2;
					try self.stack.append(self._allocator, (self.stack.items[idx0] - self.stack.items[idx1]));
				},
				'd' => {
					if (self.stack.items.len == 0) { return RuntimeError.BadStackAccess; }

					self.stack.items[self.stack.items.len - 1] -= 1;
				},
				'e' => {
					if (self.stack.items.len < 2) { return RuntimeError.BadStackAccess; }

					const idx0 = self.stack.items.len - 1;
					const idx1 = self.stack.items.len - 2;

					try self.stack.append(self._allocator, @mod(self.stack.items[idx0], self.stack.items[idx1]));
				},
				'f' => {
					if (self.stack.items.len == 0) { return RuntimeError.BadStackAccess; }
					const ch:u8 = convertToU8(self.stack.getLast());
					std.debug.print("{c}\n",.{ch});
				},
				'g' => {
					if (self.stack.items.len < 2) { return RuntimeError.BadStackAccess; }

					const idx0 = self.stack.items.len - 1;
					const idx1 = self.stack.items.len - 2;
					try self.stack.append(self._allocator, (self.stack.items[idx0] + self.stack.items[idx1]));
				},
				'h' => {
					const inp_val = try stdin_ifc.takeDelimiterExclusive('\n');
					const parsed = try std.fmt.parseInt(i32, inp_val, 10);
					try self.stack.append(self._allocator, parsed);
				},
				'i' => {
					if (self.stack.items.len == 0) { return RuntimeError.BadStackAccess; }

					self.stack.items[self.stack.items.len - 1] += 1;
				},
				'j' => {
					const chars = try stdin_ifc.takeDelimiter('\n');
					if (chars) |chrs| {
						if (chrs.len > 0) {
							try self.stack.append(self._allocator, @as(i32, chrs[0]));
						}
					}
				},
				'k' => {
					if (self.stack.items.len == 0) { return RuntimeError.BadStackAccess; }
					const top_val = self.stack.getLast();
					if (top_val == 0) { skip_next = true; }
				},
				'l' => {
					if (self.stack.items.len < 2) { return RuntimeError.BadStackAccess; }

					const idx0 = self.stack.items.len - 1;
					const idx1 = self.stack.items.len - 2;
					const temp = self.stack.items[idx0];
					self.stack.items[idx0] = self.stack.items[idx1];
					self.stack.items[idx1] = temp;
				},
				'm' => {
					if (self.stack.items.len < 2) { return RuntimeError.BadStackAccess; }

					const idx0 = self.stack.items.len - 1;
					const idx1 = self.stack.items.len - 2;
					try self.stack.append(self._allocator, (self.stack.items[idx0] * self.stack.items[idx1]));
				},
				'n' => {
					if (self.stack.items.len < 2) { return RuntimeError.BadStackAccess; }

					const idx0 = self.stack.items.len - 1;
					const idx1 = self.stack.items.len - 2;
					try self.stack.append(self._allocator, @as(i32, @intFromBool(self.stack.items[idx0] == self.stack.items[idx1])));
				},
				'o' => {
					if (self.stack.items.len == 0) { return RuntimeError.BadStackAccess; }

					_ = self.stack.pop();
				},
				'p' => {
					if (self.stack.items.len < 2) { return RuntimeError.BadStackAccess; }

					const idx0 = self.stack.items.len - 1;
					const idx1 = self.stack.items.len - 2;
					try self.stack.append(self._allocator, @divTrunc(self.stack.items[idx0], self.stack.items[idx1]));
				},
				'q' => {
					if (self.stack.items.len == 0) { return RuntimeError.BadStackAccess; }

					const top_val = self.stack.getLast();
					try self.stack.append(self._allocator, top_val);
				},
				'r' => {
					try self.stack.append(self._allocator,@as(i32, @intCast(self.stack.items.len)));
				},
				's' => {
					if (self.stack.items.len == 0) { return RuntimeError.BadStackAccess; }

					const top_val = self.stack.getLast();
					if (top_val < 0) { return RuntimeError.BadStackAccess; }
					const swap_idx = @as(u32, @intCast(top_val));
					const top_idx = self.stack.items.len - 1;
					const temp = self.stack.items[top_idx];

					self.stack.items[top_idx] = self.stack.items[swap_idx];
					self.stack.items[swap_idx] = temp;
				},
				't' => {
					if (self.stack.items.len == 0) { return RuntimeError.BadStackAccess; }

					const top_val = self.stack.getLast();
					if (top_val == 0) {
						var loop_opened:u32 = 1;
						prog_pos += 1;
						searchU: while (prog_pos < self.prog.len) {
							if ((self.prog[prog_pos] == 'u') and (loop_opened == 0)) {
								break :searchU;
							} else if (self.prog[prog_pos] == 't') {
								loop_opened += 1;
							} else if (self.prog[prog_pos] == 'u') {
								loop_opened -= 1;
							}
							prog_pos += 1;
						}
					}
				},
				'u' => {
					if (self.stack.items.len == 0) { return RuntimeError.BadStackAccess; }

					const top_val = self.stack.getLast();
					if (top_val != 0) {
						var loop_closed:u32 = 0;
						prog_pos -= 1;
						searchT: while (prog_pos >= 0) {
							if ((self.prog[prog_pos] == 't') and (loop_closed == 0)) {
								break :searchT;
							} else if (self.prog[prog_pos] == 'u') {
								loop_closed += 1;
							} else if (self.prog[prog_pos] == 't') {
								loop_closed -= 1;
							}
							prog_pos -= 1;
						}
					}
				},
				'v' => {
					if (self.stack.items.len == 0) { return RuntimeError.BadStackAccess; }

					self.stack.items[self.stack.items.len - 1] += 5;
				},
				'w' => {
					if (self.stack.items.len == 0) { return RuntimeError.BadStackAccess; }

					self.stack.items[self.stack.items.len - 1] -= 5;
				},
				'x' => {
					if (self.stack.items.len == 0) { return RuntimeError.BadStackAccess; }
					std.debug.print("{d}\n",.{self.stack.getLast()});
				},
				'y' => {
					self.clearStack();
				},
				'z' => {
					return;
				},
				else => std.debug.print("Invalid character {c} at {d}\n", .{cmd, prog_pos}),
			}
			prog_pos += 1;
		}
	}

	pub fn analyze(prog: []const u8) ProcessError!usize {
		std.debug.print("\nANALYZING\n", .{});
		return try processProgram(prog, null);
	}

	pub fn compile(self: *Self, prog: []const u8) ProcessError!usize {
		std.debug.print("\nCOMPILING\n", .{});
		return try processProgram(prog, self);
	}

	pub fn print(self: *Self) void {
		std.debug.print("\n{s}\n", .{self.prog});
	}
};

test "basic functionality" {
	var prog = try Prog.init(std.testing.allocator);
	defer prog.deinit();
	const len = try prog.compile(Prog.Samples.prog_hello_world);
	std.debug.print("Prog {d} symbols:\n",.{len});

	var threaded: std.Io.Threaded = .init_single_threaded;
	defer threaded.deinit();
	const io = threaded.io();
	try prog.run(io);
	prog.resetProg();
}

test "Cycle" {
	var prog = try Prog.init(std.testing.allocator);
	defer prog.deinit();
	const len = try prog.compile("avtdxu");// push 5 to top and decrement it in loop until it is 0.
	std.debug.print("Prog {d} symbols:\n",.{len});

	var threaded: std.Io.Threaded = .init_single_threaded;
	defer threaded.deinit();
	const io = threaded.io();
	try prog.run(io);
	try expect(prog.getTopStackValOrNull().? == 0);
}

test "Factorial 5" {
	var prog = try Prog.init(std.testing.allocator);
	defer prog.deinit();
	const len = try prog.compile("avqdtmldubx");// compute 5!
	std.debug.print("Prog {d} symbols:\n",.{len});

	var threaded: std.Io.Threaded = .init_single_threaded;
	defer threaded.deinit();
	const io = threaded.io();
	try prog.run(io);
	try expect(prog.getTopStackValOrNull().? == 120);
}

test "Remove comments" {
	var ssl_prog = try Prog.init(std.testing.allocator);
	defer ssl_prog.deinit();
	const len = try ssl_prog.compile("htxux#qq");

	std.debug.print("Prog {d} symbols:\n",.{len});
	ssl_prog.print();
	try expect(ssl_prog.prog.len == 5);
}

test "Zero source" {
	var ssl_prog = try Prog.init(std.testing.allocator);
	defer ssl_prog.deinit();
	const len = try ssl_prog.compile("");
	std.debug.print("Prog {d} symbols:\n",.{len});
	try expect(ssl_prog.prog.len == 0);
}

test "Bad syntax" {
	var ssl_prog = try Prog.init(std.testing.allocator);
	defer ssl_prog.deinit();
	if (ssl_prog.compile("h1txux#qq")) |_| {
		try expect(false);
	} else |err| switch (err) {
		Prog.ProcessError.SyntaxError => try expect(true),
		else => try expect(false)
	}
	try expect(true);
}