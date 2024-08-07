// In this file modules may be enabled or disabled

pub const mist = @import("shell.zig");

pub const clear = @import("modules/clear.zig");
pub const id = @import("modules/id.zig");
pub const yes = @import("modules/yes.zig");
pub const reset = @import("modules/reset.zig");
pub const ls = @import("modules/ls.zig");
pub const print = @import("modules/print.zig");
pub const getenv = @import("modules/getenv.zig");
pub const time = @import("modules/time.zig");
pub const base91 = @import("modules/base91.zig");
pub const gz = @import("modules/gz.zig");
pub const @"true" = @import("modules/true.zig");
pub const @"false" = @import("modules/false.zig");

// Shell builtins
pub const @">" = @import("shell/builtins/>.zig");
pub const @"<" = @import("shell/builtins/<.zig");
pub const @"#" = @import("shell/builtins/#.zig");
pub const @"#!" = @import("shell/builtins/#.zig");
pub const @"if" = @import("shell/builtins/if.zig");
pub const cd = @import("shell/builtins/cd.zig");
pub const commands = @import("shell/builtins/commands.zig");
pub const exit = @import("shell/builtins/exit.zig");
pub const history = @import("shell/builtins/history.zig");
pub const prompt = @import("shell/builtins/prompt.zig");
pub const set = @import("shell/builtins/set.zig");
pub const unset = @import("shell/builtins/unset.zig");

//pub const wasm = @import("modules/wasm.zig");
