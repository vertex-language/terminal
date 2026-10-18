package workspace

import (
    "os/env"
    "os/process"
    "os/pty"
    "os/user"
    "terminal/view"
    "terminal/vt"
    "ui/state"
)

/// A shell running in a terminal: the pseudo-terminal it runs under, the
/// emulator keeping its screen, and what is waiting to be written to it.
@MainActor
final class Shell {
    let term: vt.Terminal
    var session: pty.Session? = nil
    /// Bytes for the shell, written in order by one task at a time.
    var outbox: [uint8] = []
    var writing = false
    /// Why it couldn't start, shown on its screen.
    var failure: string? = nil
    /// Told when the screen changed (output arrived) and when the shell
    /// has ended.
    weak var owner: Controller? = nil
    var paneID = 0
    var selection: view.Selection? = nil
    /// The program has ended; its pane stays (closeOnExit) until closed
    /// or restarted.
    var Exited = false
    var ExitCode = 0
    /// What it was started with, to start it again (restartConnection).
    var startedCommand: [string] = []
    var startedDir: string? = nil
    var startedEnv: [string: string] = [:]
    /// Bumped on each start, so an old run's end is told apart from the
    /// new one's.
    var generation = 0

    init(columns: int, rows: int) {
        term = vt.Terminal(columns: columns, rows: rows)
    }

    /// Starts a program (a commandline, or "" for the user's shell as a
    /// login shell) in dir (or the home directory), with env added.
    func Start(commandline: string, dir: string?, env extra: [string: string] = [:]) {
        var args = splitCommandline(commandline)
        if args.isEmpty { args = [env.Get("SHELL") ?? "/bin/zsh", "-l"] }
        startedCommand = args
        startedDir = dir
        startedEnv = extra
        spawn()
    }

    func spawn() {
        generation += 1
        Exited = false
        ExitCode = 0
        failure = nil
        let args = startedCommand
        var program = args[0]
        if !program.hasPrefix("/") {
            if let found = process.Find(program) { program = found }
        }
        var cmd = process.Command(program, [string](args.dropFirst()))
        cmd.Env["TERM"] = "xterm-256color"
        cmd.Env["COLORTERM"] = "truecolor"
        cmd.Env["TERM_PROGRAM"] = "vertex-terminal"
        cmd.Env["TERM_PROGRAM_VERSION"] = "0.2"
        if env.Get("LANG") == nil { cmd.Env["LANG"] = "en_US.UTF-8" }
        for (k, v) in startedEnv { cmd.Env[k] = expandEnv(v) }
        cmd.Dir = expandHome(startedDir) ?? user.Home()
        do {
            let s = try pty.Spawn(cmd, size: pty.Size(columns: term.Columns, rows: term.Rows))
            session = s
            let gen = generation
            Task { await self.pump(s, gen) }
        } catch {
            failure = "\(error)"
            term.Feed("\u{1b}[31mCan't start \(args[0]): \(error)\u{1b}[0m\r\n")
            Exited = true
            ExitCode = -1
            owner?.ShellOutput(paneID)
            owner?.ShellExited(paneID)
        }
    }

    /// Reads what the shell writes into the screen until it ends.
    func pump(_ s: pty.Session, _ gen: int) async {
        var buf = [uint8](repeating: 0, count: 65536)
        while true {
            var n = 0
            do {
                n = try await s.Read(into: &buf)
            } catch {
                n = 0
            }
            if n == 0 { break }
            term.Feed(n == buf.count ? buf : [uint8](buf[0..<n]))
            let replies = term.TakeResponses()
            if !replies.isEmpty { Send(replies) }
            owner?.ShellOutput(paneID)
        }
        let status = try? await s.Wait()
        if gen != generation { return }
        session = nil
        s.Close()
        Exited = true
        ExitCode = exitCodeOf(status)
        owner?.ShellExited(paneID)
    }

    /// Starts the program again, in the same pane (after it ended, or on
    /// purpose).
    func Restart() {
        if let s = session {
            s.Hangup()
            s.Close()
            session = nil
        }
        term.Feed("\r\n")
        spawn()
    }

    /// Writes bytes for the shell to read, after anything written before.
    func Send(_ bytes: [uint8]) {
        if bytes.isEmpty || Exited { return }
        outbox.append(contentsOf: bytes)
        if writing { return }
        writing = true
        Task { await self.drain() }
    }

    func drain() async {
        while !outbox.isEmpty {
            let chunk = outbox
            outbox = []
            guard let s = session else { break }
            do {
                try await s.Write(chunk)
            } catch {
                outbox = []
                break
            }
        }
        writing = false
    }

    /// Gives the terminal a new size, and the shell with it.
    func Resize(columns: int, rows: int, width: int, height: int) {
        if columns == term.Columns && rows == term.Rows { return }
        term.Resize(columns: columns, rows: rows)
        selection = nil
        try? session?.Resize(pty.Size(columns: columns, rows: rows, width: width, height: height))
    }

    /// What the shell is running in the foreground ("zsh", "vim").
    var ProcessName: string? { return session?.ForegroundName() }

    /// Where the shell is: the directory it reported (OSC 7), or that of
    /// what it runs in the foreground.
    var Directory: string? {
        if let d = term.WorkingDirectory { return d }
        return session?.ForegroundDir()
    }

    /// Whether something other than the shell itself runs in the
    /// foreground: what closing the pane would interrupt.
    var Busy: bool {
        guard let name = ProcessName, !Exited else { return false }
        let shellName = String((startedCommand.first ?? "").split(separator: "/").last ?? "")
        return name != shellName && name != "-" + shellName && !["zsh", "bash", "fish", "sh", "login", "-zsh", "-bash"].contains(name)
    }

    /// Ends it: the shell sees the terminal hang up.
    func Close() {
        owner = nil
        generation += 1
        if let s = session {
            s.Hangup()
            s.Close()
        }
        session = nil
    }
}

func exitCodeOf(_ status: process.ExitStatus?) -> int {
    guard let s = status else { return 0 }
    return int(s.Code ?? -1)
}

/// A command line as a shell would split it: words, with quotes and
/// backslashes.
func splitCommandline(_ s: string) -> [string] {
    var out: [string] = []
    var cur: [uint8] = []
    var any = false
    var quote: uint8 = 0
    let b = [uint8](s.utf8)
    var i = 0
    while i < b.count {
        let c = b[i]
        if quote != 0 {
            if c == quote {
                quote = 0
            } else if c == 0x5C && quote == 0x22 && i + 1 < b.count {
                cur.append(b[i + 1])
                i += 1
            } else {
                cur.append(c)
            }
        } else if c == 0x22 || c == 0x27 {
            quote = c
            any = true
        } else if c == 0x5C && i + 1 < b.count {
            cur.append(b[i + 1])
            any = true
            i += 1
        } else if c == 0x20 || c == 0x09 {
            if any || !cur.isEmpty {
                out.append(string(decoding: cur, as: UTF8.self))
                cur = []
                any = false
            }
        } else {
            cur.append(c)
        }
        i += 1
    }
    if any || !cur.isEmpty { out.append(string(decoding: cur, as: UTF8.self)) }
    return out
}

/// ~ and ~/ at the start of a path as the home directory.
func expandHome(_ p: string?) -> string? {
    guard let path = p, !path.isEmpty else { return nil }
    if path == "~" || path == "%USERPROFILE%" { return user.Home() }
    if path.hasPrefix("~/") { return (user.Home() ?? "") + String(path.dropFirst(1)) }
    return path
}

/// ${NAME} and %NAME% in a value, from the environment.
func expandEnv(_ v: string) -> string {
    let b = [uint8](v.utf8)
    var out: [uint8] = []
    var i = 0
    while i < b.count {
        if b[i] == 0x24 && i + 1 < b.count && b[i + 1] == 0x7B {
            var j = i + 2
            while j < b.count && b[j] != 0x7D { j += 1 }
            if j < b.count {
                let name = string(decoding: [uint8](b[(i + 2)..<j]), as: UTF8.self)
                out.append(contentsOf: [uint8]((env.Get(name) ?? "").utf8))
                i = j + 1
                continue
            }
        }
        if b[i] == 0x25 {
            var j = i + 1
            while j < b.count && b[j] != 0x25 { j += 1 }
            if j < b.count && j > i + 1 {
                let name = string(decoding: [uint8](b[(i + 1)..<j]), as: UTF8.self)
                if let val = env.Get(name) {
                    out.append(contentsOf: [uint8](val.utf8))
                    i = j + 1
                    continue
                }
            }
        }
        out.append(b[i])
        i += 1
    }
    return string(decoding: out, as: UTF8.self)
}

/// A path with the home directory as ~, and only its last two parts.
func shortPath(_ path: string) -> string {
    var p = path
    if let home = user.Home(), p.hasPrefix(home) {
        p = "~" + String(p.dropFirst(home.count))
    }
    let parts = p.split(separator: "/")
    if parts.count <= 2 { return p.isEmpty ? "/" : p }
    return "…/" + String(parts[parts.count - 2]) + "/" + String(parts[parts.count - 1])
}
