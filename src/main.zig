const std = @import("std");
const SillyStack = @import("SillyStack");

pub fn readFileToString(allocator: std.mem.Allocator, io: std.Io, file_path: []const u8) ![]u8 {
	const cwd = std.Io.Dir.cwd();

	var file = try cwd.openFile(io, file_path, .{.mode = .read_only});
	defer file.close(io);

	var stat = try file.stat(io);
	const prog_buf = try allocator.alloc(u8, stat.size);
	errdefer allocator.free(prog_buf);

	var file_buf: [1024]u8 = undefined;
	var fr = file.reader(io, &file_buf);
	var reader = &fr.interface;

	try reader.readSliceAll(prog_buf);

	return prog_buf;
}

pub fn main() !void {
	var threaded: std.Io.Threaded = .init_single_threaded;
	defer threaded.deinit();
	const io = threaded.io();
	
	const allocator = std.heap.page_allocator;

	const args = try std.process.argsAlloc(allocator);
	defer std.process.argsFree(allocator, args);

	if (args.len < 2) {
		// No args provided - run a sample program requesting to input a number
		// and calculating its factorial.
		var prog_factorial = try SillyStack.Prog.init(allocator);
		defer prog_factorial.deinit();
		_ = try prog_factorial.compile(SillyStack.Prog.Samples.PROG_FACTORIAL);
		try prog_factorial.run(io);
	} else {
		const file_path = args[1];
		const prog_text = try readFileToString(allocator, io, file_path);
		defer allocator.free(prog_text);
		std.debug.print("\n{s}\n", .{prog_text});

		var ssl_prog = try SillyStack.Prog.init(allocator);
		defer ssl_prog.deinit();
		_ = try ssl_prog.compile(prog_text);
		ssl_prog.print();
		try ssl_prog.run(io);
	}
}
