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
    var tabID = 0
    var selection: view.Selection? = nil

    init(columns: int, rows: int) {
        term = vt.Terminal(columns: columns, rows: rows)
    }

    /// Starts the user's shell, as a login shell, in dir (or the home
    /// directory).
    func Start(dir: string?) {
        let shell = env.Get("SHELL") ?? "/bin/zsh"
        var cmd = process.Command(shell, ["-l"])
        cmd.Env["TERM"] = "xterm-256color"
        cmd.Env["COLORTERM"] = "truecolor"
        cmd.Env["TERM_PROGRAM"] = "vertex-terminal"
        cmd.Env["TERM_PROGRAM_VERSION"] = "0.1"
        if env.Get("LANG") == nil { cmd.Env["LANG"] = "en_US.UTF-8" }
        cmd.Dir = dir ?? user.Home()
        do {
            let s = try pty.Spawn(cmd, size: pty.Size(columns: term.Columns, rows: term.Rows))
            session = s
            Task { await self.pump(s) }
        } catch {
            failure = "\(error)"
            term.Feed("\u{1b}[31mCan't start \(shell): \(error)\u{1b}[0m\r\n")
            owner?.ShellOutput(tabID)
        }
    }

    /// Reads what the shell writes into the screen until it ends.
    func pump(_ s: pty.Session) async {
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
            owner?.ShellOutput(tabID)
        }
        let status = try? await s.Wait()
        session = nil
        s.Close()
        _ = status
        owner?.ShellExited(tabID)
    }

    /// Writes bytes for the shell to read, after anything written before.
    func Send(_ bytes: [uint8]) {
        if bytes.isEmpty { return }
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

    /// Ends it: the shell sees the terminal hang up.
    func Close() {
        owner = nil
        if let s = session {
            s.Hangup()
            s.Close()
        }
        session = nil
    }
}

/// A tab: a shell and what its tab shows.
@Observable @MainActor
final class Tab {
    let ID: int
    let shell: Shell
    var Title = "Terminal"
    /// The bell rang while the tab was behind another.
    var Bell = false
    var seenBells = 0

    init(id: int, shell: Shell) {
        ID = id
        self.shell = shell
    }

    /// The tab's title from the shell: what the program set (OSC 0 or 2),
    /// or what is running and where.
    func UpdateTitle() {
        var t = shell.term.Title
        if t.isEmpty {
            let name = shell.ProcessName ?? "Terminal"
            if let d = shell.Directory {
                t = "\(name) — \(shortPath(d))"
            } else {
                t = name
            }
        }
        if t != Title { Title = t }
    }
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

/// Every tab, and which is in front.
@Observable @MainActor
final class Workspace {
    var Tabs: [Tab] = []
    var Active = 0
    var next = 1

    init() {}

    var Current: Tab? {
        for t in Tabs where t.ID == Active { return t }
        return Tabs.first
    }

    func Index(of id: int) -> int? {
        for i in 0..<Tabs.count where Tabs[i].ID == id { return i }
        return nil
    }
}
