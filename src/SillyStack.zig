const std = @import("std");
const expect = std.testing.expect;
const mem = std.mem;
const Allocator = mem.Allocator;

pub const Prog = struct {
	const Self = @This();
	const DEFAULT_STACK_SIZE: u32 = 256;

	_allocator: Allocator,
	prog: []u8,
	stack: std.ArrayList(i32),

	pub const Samples = struct {
		pub const PROG_HELLO_WORLD: [] const u8 = "avqmimcfdddfviiffvddfavdegmfavdmcwfwdddfvddfwdfwdddf";
		pub const PROG_CAT: [] const u8 = "jf";
		pub const PROG_FACTORIAL: [] const u8 =
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

	pub fn getTopVal(self: *Self) RuntimeError!i32 {
		if (self.stack.items.len == 0) { return RuntimeError.BadStackAccess; }
		return self.stack.getLast();
	}

	pub fn setTopVal(self: *Self, val:i32) RuntimeError!i32 {
		if (self.stack.items.len == 0) { return RuntimeError.BadStackAccess; }
		self.stack.items[self.stack.items.len - 1] = val;
	}

	pub fn incTopVal(self: *Self, val:i32) RuntimeError!void {
		if (self.stack.items.len == 0) { return RuntimeError.BadStackAccess; }
		self.stack.items[self.stack.items.len - 1] += val;
	}

	fn getTop2Idx(self: *Self) RuntimeError!struct { usize, usize } {
		if (self.stack.items.len < 2) { return RuntimeError.BadStackAccess; }
		const idx0 = self.stack.items.len - 1;
		const idx1 = self.stack.items.len - 2;
		return .{idx0, idx1};
	}

	fn getTop2Val(self: *Self) RuntimeError!struct { a: i32, b: i32 } {
		if (self.stack.items.len < 2) return RuntimeError.BadStackAccess;
		return .{
			.a = self.stack.items[self.stack.items.len - 1],
			.b = self.stack.items[self.stack.items.len - 2],
		};
	}

	pub const ProcessError = error {
		SyntaxError,
		AllocationFailed
	};

	pub const RuntimeError = error {
		BadStackAccess,
		BadOffset,
		CmdNotImplemented,
		UnmatchedLoop,
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
		var prog_pos: i32 = 0;
		const prog_len: i32 = @intCast(self.prog.len);
		var skip_next: bool = false;
		self.clearStack();
		var stdin_buffer: [512]u8 = undefined;
		var stdin_reader = std.Io.File.stdin().reader(io, &stdin_buffer);
		const stdin_ifc = &stdin_reader.interface;

		while (prog_pos < prog_len) {
			if (skip_next) {
				skip_next = false;
				prog_pos += 1;
				continue;
			}
			const cmd = self.prog[@intCast(prog_pos)];
			switch (cmd) {
				'a' => try self.stack.append(self._allocator, 0),
				'b' => _ = self.stack.pop(),
				'c' => {
					const vals = try self.getTop2Val();

					try self.stack.append(self._allocator, (vals.a - vals.b));
				},
				'd' => {
					if (self.stack.items.len == 0) { return RuntimeError.BadStackAccess; }

					self.stack.items[self.stack.items.len - 1] -= 1;
				},
				'e' => {
					const vals = try self.getTop2Val();

					try self.stack.append(self._allocator, @mod(vals.a, vals.b));
				},
				'f' => {
					const top_val = try self.getTopVal();
					const ch:u8 = convertToU8(top_val);
					std.debug.print("{c}",.{ch});
				},
				'g' => {
					const vals = try self.getTop2Val();

					try self.stack.append(self._allocator, (vals.a + vals.b));
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
					const top_val = try self.getTopVal();
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
					const vals = try self.getTop2Val();

					try self.stack.append(self._allocator, (vals.a * vals.b));
				},
				'n' => {
					const vals = try self.getTop2Val();

					try self.stack.append(self._allocator, @as(i32, @intFromBool(vals.a == vals.b)));
				},
				'o' => {
					if (self.stack.items.len == 0) { return RuntimeError.BadStackAccess; }

					_ = self.stack.pop();
				},
				'p' => {
					const vals = try self.getTop2Val();
					try self.stack.append(self._allocator, @divTrunc(vals.a, vals.b));
				},
				'q' => {
					const top_val = try self.getTopVal();
					try self.stack.append(self._allocator, top_val);
				},
				'r' => {
					try self.stack.append(self._allocator,@as(i32, @intCast(self.stack.items.len)));
				},
				's' => {
					const top_val = try self.getTopVal();
					if (top_val < 0) { return RuntimeError.BadOffset; }

					const swap_idx: usize = @intCast(top_val);
					const top_idx = self.stack.items.len - 1;
					const temp = self.stack.items[top_idx];

					self.stack.items[top_idx] = self.stack.items[swap_idx];
					self.stack.items[swap_idx] = temp;
				},
				't' => {
					const top_val = try self.getTopVal();
					if (top_val == 0) {
						var loop_depth: i32 = 1;
						prog_pos += 1;
						while (prog_pos < prog_len and loop_depth > 0) {
							if (self.prog[@intCast(prog_pos)] == 't') {
								loop_depth += 1;
							} else if (self.prog[@intCast(prog_pos)] == 'u') {
								loop_depth -= 1;
							}
							if (loop_depth > 0) prog_pos += 1;
						}
						if (loop_depth != 0) { return RuntimeError.UnmatchedLoop; }
					}
				},
				'u' => {
					const top_val = try self.getTopVal();
					if (top_val != 0) {
						var loop_depth: i32 = 1;
						prog_pos -= 1;
						while (prog_pos >= 0 and loop_depth > 0) {
							if (self.prog[@intCast(prog_pos)] == 'u') {
								loop_depth += 1;
							} else if (self.prog[@intCast(prog_pos)] == 't') {
								loop_depth -= 1;
							}
							if (loop_depth > 0) prog_pos -= 1;
						}
						if (loop_depth != 0) { return RuntimeError.UnmatchedLoop; }
					}
				},
				'v' => {
					try self.incTopVal(5);
				},
				'w' => {
					try self.incTopVal(-5);
				},
				'x' => {
					const top_val = try self.getTopVal();
					std.debug.print("{d}\n",.{top_val});
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
	const len = try prog.compile(Prog.Samples.PROG_HELLO_WORLD);
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